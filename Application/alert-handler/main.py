import os
import json
import time
import logging
import boto3

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

ALERT_QUEUE_URL = os.getenv('ALERT_QUEUE_URL')
OVERRIDE_QUEUE_URL = os.getenv('OVERRIDE_QUEUE_URL')
EXECUTION_REGISTRY_NAME = os.getenv('EXECUTION_REGISTRY_NAME')
STEP_FUNCTION_ARN = os.getenv('STEP_FUNCTION_ARN')
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
    if alert_type == 'false_positive':
        wait_seconds = get_ssm_parameter("/smart-helmet/config/false_positive_window_seconds", 5)
        message = f"False positive detected. Countdown: {wait_seconds}s"
    elif alert_type == 'standard':
        wait_seconds = get_ssm_parameter("/smart-helmet/config/standard_alert_window_seconds", 30)
        message = f"Crash detected. Countdown: {wait_seconds}s"
    else:
        wait_seconds = get_ssm_parameter("/smart-helmet/config/retrospective_alert_window_seconds", 300)
        message = f"Retrospective crash detected. Countdown: {wait_seconds}s"

    # 1. Publish START COUNTDOWN to Helmet
    publish_to_helmet(helmet_id, "START_COUNTDOWN", message)

    # 2. Start Step Function Execution
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
        
        # 3. Write ARN to Execution Registry DynamoDB Table
        table = dynamodb.Table(EXECUTION_REGISTRY_NAME)
        table.put_item(
            Item={
                'helmetId': helmet_id,
                'ExecutionArn': execution_arn,
                'TimeToExist': int(time.time()) + (wait_seconds + 60)
            }
        )
        logging.info(f"Started Step Function {execution_arn} for {helmet_id}")

    except Exception as e:
        logging.error(f"Failed to start step function: {str(e)}")

def handle_override(msg):
    body = json.loads(msg['Body'])
    helmet_id = body.get('helmet_id')
    
    if not helmet_id:
        return

    # 1. Look up execution ARN
    table = dynamodb.Table(EXECUTION_REGISTRY_NAME)
    try:
        response = table.get_item(Key={'helmetId': helmet_id})
        item = response.get('Item')
        
        if item and 'ExecutionArn' in item:
            execution_arn = item['ExecutionArn']
            
            # 2. Stop Execution
            try:
                sfn.stop_execution(
                    executionArn=execution_arn,
                    error="CancelledByRider",
                    cause="The rider pressed the cancel button."
                )
                logging.info(f"Stopped execution {execution_arn} for {helmet_id}")
            except sfn.exceptions.ExecutionDoesNotExist:
                logging.warning(f"Execution {execution_arn} already finished or does not exist.")

            # 3. Publish DISMISS to helmet
            publish_to_helmet(helmet_id, "DISMISS", "Alert cancelled successfully.")

            # 4. Remove from registry
            table.delete_item(Key={'helmetId': helmet_id})
        else:
            logging.warning(f"No active execution found for {helmet_id} to override.")

    except Exception as e:
        logging.error(f"Failed to process override for {helmet_id}: {str(e)}")

def process_messages():
    if not ALERT_QUEUE_URL or not OVERRIDE_QUEUE_URL or not STEP_FUNCTION_ARN or not EXECUTION_REGISTRY_NAME:
        logging.error("Missing required environment variables.")
        return

    while True:
        try:
            # Poll Alert Queue
            alert_res = sqs.receive_message(QueueUrl=ALERT_QUEUE_URL, MaxNumberOfMessages=5, WaitTimeSeconds=5)
            for msg in alert_res.get('Messages', []):
                logging.info(f"Received ALERT message: {msg['Body']}")
                handle_alert(msg)
                sqs.delete_message(QueueUrl=ALERT_QUEUE_URL, ReceiptHandle=msg['ReceiptHandle'])

            # Poll Override Queue
            override_res = sqs.receive_message(QueueUrl=OVERRIDE_QUEUE_URL, MaxNumberOfMessages=5, WaitTimeSeconds=5)
            for msg in override_res.get('Messages', []):
                logging.info(f"Received OVERRIDE message: {msg['Body']}")
                handle_override(msg)
                sqs.delete_message(QueueUrl=OVERRIDE_QUEUE_URL, ReceiptHandle=msg['ReceiptHandle'])

        except Exception as e:
            logging.error(f"Error in polling loop: {str(e)}")
            time.sleep(5)

if __name__ == '__main__':
    logging.info("Starting Alert Handler Service...")
    process_messages()
