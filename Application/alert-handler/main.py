import os
import json
import time
import logging
import boto3
import signal
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from decimal import Decimal

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

ALERT_QUEUE_URL = os.getenv('ALERT_QUEUE_URL')
OVERRIDE_QUEUE_URL = os.getenv('OVERRIDE_QUEUE_URL')
EXECUTION_REGISTRY_NAME = os.getenv('EXECUTION_REGISTRY_NAME')
STEP_FUNCTION_ARN = os.getenv('STEP_FUNCTION_ARN')
RECONCILIATION_STEP_FUNCTION_ARN = os.getenv('RECONCILIATION_STEP_FUNCTION_ARN')
IOT_ENDPOINT_URL = os.getenv('IOT_ENDPOINT_URL')

sqs = boto3.client('sqs', region_name='ap-south-1')
dynamodb = boto3.resource('dynamodb', region_name='ap-south-1')
sfn = boto3.client('stepfunctions', region_name='ap-south-1')

if IOT_ENDPOINT_URL:
    iot_data = boto3.client('iot-data', region_name='ap-south-1', endpoint_url=f"https://{IOT_ENDPOINT_URL}")
else:
    iot_data = boto3.client('iot-data', region_name='ap-south-1')

def publish_to_helmet(helmet_id, action, message):
    try:
        topic = f"helmet/{helmet_id}/alert/status"
        payload = {
            "action": action,
            "message": message,
            "timestamp": int(time.time())
        }
        iot_data.publish(
            topic=topic,
            qos=1,
            payload=json.dumps(payload)
        )
        logging.info(f"Published {action} to {topic}")
    except Exception as e:
        logging.error(f"Failed to publish to IoT Core: {str(e)}")

def get_ssm_parameter(name, default_value):
    try:
        ssm = boto3.client('ssm', region_name='ap-south-1')
        response = ssm.get_parameter(Name=name)
        return int(response['Parameter']['Value'])
    except Exception as e:
        logging.warning(f"Failed to fetch {name} from SSM, using default {default_value}: {str(e)}")
        return default_value

def handle_alert(msg):
    body = json.loads(msg['Body'])
    helmet_id = body.get('helmet_id')
    timestamp = body.get('timestamp')
    alert_type = body.get('alert_type')

    if not helmet_id:
        return

    # Fetch configuration from SSM Parameter Store as requested for production readiness
    if alert_type == 'FP_CD':
        status = 'FP_CD'
        wait_seconds = get_ssm_parameter("/smart-helmet/config/false_positive_window_seconds", 5)
        message = f"False positive detected. Countdown: {wait_seconds}s"
    elif alert_type == 'retrospective':
        status = 'STD_CD'
        wait_seconds = get_ssm_parameter("/smart-helmet/config/retrospective_alert_window_seconds", 300)
        message = f"Retrospective crash detected. Countdown: {wait_seconds}s"
    elif alert_type == 'STD_CD':
        status = 'STD_CD'
        wait_seconds = get_ssm_parameter("/smart-helmet/config/standard_alert_window_seconds", 30)
        message = f"Crash detected. Countdown: {wait_seconds}s"
    else:
        status = 'STD_CD'
        wait_seconds = get_ssm_parameter("/smart-helmet/config/standard_alert_window_seconds", 30)
        message = f"Crash detected. Countdown: {wait_seconds}s"

    table = dynamodb.Table(EXECUTION_REGISTRY_NAME)

    try:
        execution_input = {
            "helmet_id": helmet_id,
            "timestamp": timestamp,
            "wait_seconds": wait_seconds
        }
        response = sfn.start_execution(
            stateMachineArn=STEP_FUNCTION_ARN,
            input=json.dumps(execution_input)
        )
        execution_arn = response['executionArn']
        
        # Write ARN and status to Execution Registry DynamoDB Table
        table.put_item(
            Item={
                'helmetId': helmet_id,
                'ExecutionArn': execution_arn,
                'status': status,
                'timestamp': Decimal(str(timestamp)),
                'TimeToExist': int(time.time()) + (wait_seconds + 60)
            }
        )
        logging.info(f"Started Step Function {execution_arn} with status {status} for {helmet_id}")

        publish_to_helmet(helmet_id, "START_COUNTDOWN", message)

    except Exception as e:
        logging.error(f"Failed to start step function: {str(e)}")

def handle_override(msg):
    body = json.loads(msg['Body'])
    helmet_id = body.get('helmet_id')
    action = body.get('action')
    timestamp = body.get('timestamp', int(time.time()))
    
    if not helmet_id:
        return

    table = dynamodb.Table(EXECUTION_REGISTRY_NAME)
    try:
        # Scenario 2A: False Positive Override
        if action == 'FP_OVERRIDE':
            logging.info(f"Rider override FP_OVERRIDE received for {helmet_id}. Triggering standard countdown.")
            
            # Read standard warning countdown seconds
            standard_wait = get_ssm_parameter("/smart-helmet/config/standard_alert_window_seconds", 30)
            execution_input = {
                "helmet_id": helmet_id,
                "timestamp": timestamp,
                "wait_seconds": standard_wait
            }
            response = sfn.start_execution(
                stateMachineArn=STEP_FUNCTION_ARN,
                input=json.dumps(execution_input)
            )
            execution_arn = response['executionArn']
            
            # Upsert registry row to STD_CD
            table.put_item(
                Item={
                    'helmetId': helmet_id,
                    'ExecutionArn': execution_arn,
                    'status': 'STD_CD',
                    'timestamp': Decimal(str(timestamp)),
                    'TimeToExist': int(time.time()) + (standard_wait + 60)
                }
            )
            
            # Publish standard countdown warn
            message = f"Crash warning active. Countdown: {standard_wait}s"
            publish_to_helmet(helmet_id, "START_COUNTDOWN", message)

        # Scenario 1A/1B: Cancellation
        elif action in ['cancel', 'CANCEL']:
            response = table.get_item(Key={'helmetId': helmet_id})
            item = response.get('Item')
            
            if item:
                # Scenario 1A: Active countdown exists
                execution_arn = item['ExecutionArn']
                logging.info(f"Rider cancel received during active countdown for {helmet_id}. Updating registry status to CANCEL.")
                
                table.put_item(
                    Item={
                        'helmetId': helmet_id,
                        'ExecutionArn': execution_arn,
                        'status': 'CANCEL',
                        'timestamp': item.get('timestamp', Decimal(str(timestamp))),
                        'TimeToExist': int(time.time()) + 60
                    }
                )
                publish_to_helmet(helmet_id, "DISMISS", "Alert cancelled successfully.")
            
            else:
                # Scenario 1B: Late Cancel (registry row missing)
                logging.warning(f"Rider cancel received but registry row is missing for {helmet_id}. Starting SFN2 reconciliation.")
                
                # Calculate if late cancel criteria are met:
                # ts2 - ts1 < 30 seconds AND t_now - ts1 < 300 seconds
                ts1 = float(timestamp) # crash timestamp
                ts2 = float(body.get('timestamp', time.time())) # rider override timestamp
                t_now = time.time()
                is_reconcilable = (ts2 - ts1 < 30) and (t_now - ts1 < 300)
                
                reconcile_input = {
                    "helmet_id": helmet_id,
                    "timestamp": timestamp,
                    "is_reconcilable": is_reconcilable
                }
                
                rec_response = sfn.start_execution(
                    stateMachineArn=RECONCILIATION_STEP_FUNCTION_ARN,
                    input=json.dumps(reconcile_input)
                )
                rec_execution_arn = rec_response['executionArn']
                
                # Write reconciliation lease to registry
                table.put_item(
                    Item={
                        'helmetId': helmet_id,
                        'ExecutionArn': rec_execution_arn,
                        'status': 'CANCEL',
                        'timestamp': Decimal(str(timestamp)),
                        'TimeToExist': int(time.time()) + 60
                    }
                )
                publish_to_helmet(helmet_id, "DISMISS", "Stand-down initiated.")

    except Exception as e:
        logging.error(f"Failed to process override for {helmet_id}: {str(e)}")

def process_messages():
    if not ALERT_QUEUE_URL or not OVERRIDE_QUEUE_URL or not STEP_FUNCTION_ARN or not EXECUTION_REGISTRY_NAME or not RECONCILIATION_STEP_FUNCTION_ARN:
        logging.error("Missing required environment variables.")
        return

    global last_poll_time
    while not is_shutting_down:
        try:
            last_poll_time = time.time()
            
            # Poll Alert Queue
            alert_res = sqs.receive_message(QueueUrl=ALERT_QUEUE_URL, MaxNumberOfMessages=5, WaitTimeSeconds=2)
            for msg in alert_res.get('Messages', []):
                logging.info(f"Received ALERT message: {msg['Body']}")
                handle_alert(msg)
                sqs.delete_message(QueueUrl=ALERT_QUEUE_URL, ReceiptHandle=msg['ReceiptHandle'])

            # Poll Override Queue
            override_res = sqs.receive_message(QueueUrl=OVERRIDE_QUEUE_URL, MaxNumberOfMessages=5, WaitTimeSeconds=2)
            for msg in override_res.get('Messages', []):
                logging.info(f"Received OVERRIDE message: {msg['Body']}")
                handle_override(msg)
                sqs.delete_message(QueueUrl=OVERRIDE_QUEUE_URL, ReceiptHandle=msg['ReceiptHandle'])

        except Exception as e:
            logging.error(f"Error in polling loop: {str(e)}")
            time.sleep(5)
            
    logging.info("Graceful shutdown complete. Exiting.")

# --- Graceful Shutdown ---
is_shutting_down = False

def sigterm_handler(signum, frame):
    global is_shutting_down
    logging.info("Received SIGTERM. Initiating graceful shutdown...")
    is_shutting_down = True

signal.signal(signal.SIGTERM, sigterm_handler)
signal.signal(signal.SIGINT, sigterm_handler)

# --- Health Check Server ---
last_poll_time = time.time()

class HealthCheckHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            # Check for zombie task
            if time.time() - last_poll_time > 300:
                self.send_response(500)
                self.end_headers()
                self.wfile.write(b"ZOMBIE TASK")
                return

            self.send_response(200)
            self.send_header('Content-type', 'text/plain')
            self.end_headers()
            self.wfile.write(b"HEALTHY")
        else:
            self.send_response(404)
            self.end_headers()
            
    def log_message(self, format, *args):
        pass

def start_health_server():
    server = HTTPServer(('0.0.0.0', 8080), HealthCheckHandler)
    logging.info("Health check server listening on port 8080")
    server.serve_forever()

if __name__ == '__main__':
    logging.info("Starting Alert Handler Service...")
    health_thread = threading.Thread(target=start_health_server, daemon=True)
    health_thread.start()
    process_messages()
