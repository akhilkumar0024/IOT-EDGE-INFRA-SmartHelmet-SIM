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

CRASH_QUEUE_URL = os.getenv('CRASH_QUEUE_URL')
ALERT_QUEUE_URL = os.getenv('ALERT_QUEUE_URL')
CONTROL_QUEUE_URL = os.getenv('CONTROL_QUEUE_URL')
LWT_QUEUE_URL = os.getenv('LWT_QUEUE_URL')
HOT_STORAGE_NAME = os.getenv('HOT_STORAGE_NAME')
DEVICE_STATUS_DB_TABLE_NAME = os.getenv('DEVICE_STATUS_DB_TABLE_NAME')

sqs = boto3.client('sqs', region_name='ap-south-1')
dynamodb = boto3.resource('dynamodb', region_name='ap-south-1')
ssm = boto3.client('ssm', region_name='ap-south-1')

def get_ssm_parameter(name, default_value):
    try:
        response = ssm.get_parameter(Name=name)
        return int(response['Parameter']['Value'])
    except Exception as e:
        logging.warning(f"Failed to fetch {name} from SSM, using default {default_value}: {str(e)}")
        return default_value

def process_messages():
    if not CRASH_QUEUE_URL or not ALERT_QUEUE_URL or not HOT_STORAGE_NAME or not DEVICE_STATUS_DB_TABLE_NAME:
        logging.error("Missing required environment variables.")
        return

    telemetry_table = dynamodb.Table(HOT_STORAGE_NAME)
    status_table = dynamodb.Table(DEVICE_STATUS_DB_TABLE_NAME)
    
    global last_poll_time
    while not is_shutting_down:
        try:
            last_poll_time = time.time()
            
            # 1. Poll Crash Queue
            response = sqs.receive_message(
                QueueUrl=CRASH_QUEUE_URL,
                MaxNumberOfMessages=10,
                WaitTimeSeconds=2
            )

            messages = response.get('Messages', [])
            for msg in messages:
                try:
                    body = json.loads(msg['Body'], parse_float=Decimal)
                    helmet_id = body.get('helmet_id')
                    timestamp = body.get('timestamp')
                    speed = float(body.get('speed', 0))

                    logging.info(f"Processing crash event for {helmet_id} at {timestamp}")

                    # Basic Validation Logic:
                    # If speed was > 10 mph during the crash spike, consider it a genuine crash.
                    # If speed was <= 10 mph, it was probably dropped from a table or low-impact fall -> False Positive.
                    alert_type = 'standard' if speed > 10 else 'false_positive'
                    
                    logging.info(f"Validated crash as: {alert_type.upper()} (Speed: {speed})")

                    alert_event = {
                        'helmet_id': helmet_id,
                        'timestamp': timestamp,
                        'alert_type': alert_type,
                        'speed': speed,
                        'location': body.get('location', 'Unknown')
                    }

                    # Push to Alert Queue
                    sqs.send_message(
                        QueueUrl=ALERT_QUEUE_URL,
                        MessageBody=json.dumps(alert_event)
                    )
                    logging.info(f"Pushed {alert_type} alert to alert-queue for {helmet_id}")

                    # Delete from Crash Queue
                    sqs.delete_message(
                        QueueUrl=CRASH_QUEUE_URL,
                        ReceiptHandle=msg['ReceiptHandle']
                    )

                except Exception as e:
                    logging.error(f"Error processing crash event: {str(e)}")

            # 2. Poll Control Queue (Graceful Shutdowns)
            if CONTROL_QUEUE_URL:
                control_response = sqs.receive_message(
                    QueueUrl=CONTROL_QUEUE_URL,
                    MaxNumberOfMessages=10,
                    WaitTimeSeconds=2
                )
                for msg in control_response.get('Messages', []):
                    try:
                        body = json.loads(msg['Body'])
                        helmet_id = body.get('helmet_id')
                        # If we get a graceful shutdown message, write it to DynamoDB status table
                        if helmet_id:
                            logging.info(f"Received Graceful Shutdown for {helmet_id}")
                            status_table.put_item(Item={
                                'helmetId': helmet_id,
                                'status': 'GRACEFUL_SHUTDOWN',
                                'shutdown_timestamp': Decimal(str(time.time())),
                                'TimeToExist': int(time.time()) + 900 # 15 minutes TTL
                            })
                        sqs.delete_message(QueueUrl=CONTROL_QUEUE_URL, ReceiptHandle=msg['ReceiptHandle'])
                    except Exception as e:
                        logging.error(f"Error processing control event: {str(e)}")

            # 3. Poll LWT Queue
            if LWT_QUEUE_URL:
                lwt_response = sqs.receive_message(
                    QueueUrl=LWT_QUEUE_URL,
                    MaxNumberOfMessages=10,
                    WaitTimeSeconds=2
                )
                for msg in lwt_response.get('Messages', []):
                    try:
                        body = json.loads(msg['Body'])
                        helmet_id = body.get('helmet_id')
                        timestamp = body.get('timestamp', time.time())
                        
                        logging.warning(f"Received LWT Disconnect for {helmet_id}")
                        
                        # Retrieve status from the registry table using helmetId
                        db_response = status_table.get_item(Key={'helmetId': helmet_id})
                        item = db_response.get('Item', {})
                        
                        ssm_threshold = get_ssm_parameter("/smart-helmet/config/lwt_grace_period_seconds", 900)
                        
                        is_graceful = False
                        if item.get('status') == 'GRACEFUL_SHUTDOWN':
                            shutdown_time = float(item.get('shutdown_timestamp', 0))
                            if time.time() - shutdown_time < ssm_threshold:
                                is_graceful = True

                        if is_graceful:
                            logging.info(f"LWT Ignored - Helmet {helmet_id} gracefully shut down recently.")
                        else:
                            logging.error(f"GENUINE LWT: Helmet {helmet_id} dropped offline! Firing alert.")
                            alert_event = {
                                'helmet_id': helmet_id,
                                'timestamp': timestamp,
                                'alert_type': 'retrospective', # LWT triggers a retrospective emergency alert
                                'location': 'Unknown'
                            }
                            sqs.send_message(QueueUrl=ALERT_QUEUE_URL, MessageBody=json.dumps(alert_event))
                        
                        sqs.delete_message(QueueUrl=LWT_QUEUE_URL, ReceiptHandle=msg['ReceiptHandle'])
                    except Exception as e:
                        logging.error(f"Error processing LWT event: {str(e)}")

        except Exception as e:
            logging.error(f"Error polling SQS: {str(e)}")
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
    logging.info("Starting Processing Engine Service...")
    health_thread = threading.Thread(target=start_health_server, daemon=True)
    health_thread.start()
    process_messages()
