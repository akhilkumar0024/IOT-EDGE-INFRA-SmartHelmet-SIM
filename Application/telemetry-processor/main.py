import os
import json
import time
import logging
import boto3
from decimal import Decimal

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

TELEMETRY_QUEUE_URL = os.getenv('TELEMETRY_QUEUE_URL')
CRASH_QUEUE_URL = os.getenv('CRASH_QUEUE_URL')
HOT_STORAGE_NAME = os.getenv('HOT_STORAGE_NAME')

sqs = boto3.client('sqs', region_name='ap-south-1')
dynamodb = boto3.resource('dynamodb', region_name='ap-south-1')

def parse_floats_to_decimals(obj):
    if isinstance(obj, float):
        return Decimal(str(obj))
    if isinstance(obj, dict):
        return {k: parse_floats_to_decimals(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [parse_floats_to_decimals(v) for v in obj]
    return obj

def process_messages():
    if not TELEMETRY_QUEUE_URL or not HOT_STORAGE_NAME:
        logging.error("Missing required environment variables: TELEMETRY_QUEUE_URL, HOT_STORAGE_NAME")
        return

    table = dynamodb.Table(HOT_STORAGE_NAME)

    while True:
        try:
            response = sqs.receive_message(
                QueueUrl=TELEMETRY_QUEUE_URL,
                MaxNumberOfMessages=10,
                WaitTimeSeconds=10
            )

            messages = response.get('Messages', [])
            for msg in messages:
                try:
                    # Parse the payload. Boto3 DynamoDB requires floats to be Decimals.
                    body = json.loads(msg['Body'], parse_float=Decimal)
                    
                    helmet_id = body.get('helmet_id')
                    timestamp = body.get('timestamp')
                    crash_flag = body.get('crash_flag', False)
                    
                    if not helmet_id or not timestamp:
                        logging.warning(f"Invalid payload missing helmet_id or timestamp: {body}")
                        continue
                        
                    # 1. Write to Hot Storage (DynamoDB)
                    item = {
                        'helmetId': helmet_id,
                        'timestamp': Decimal(str(timestamp)),
                        'accelerometer': body.get('accelerometer', {}),
                        'speed': body.get('speed', Decimal('0')),
                        'crash_flag': crash_flag,
                        'TimeToExist': int(time.time()) + (7 * 24 * 3600) # 7 days TTL
                    }
                    
                    table.put_item(Item=item)
                    logging.info(f"Saved telemetry for {helmet_id} at {timestamp}")

                    # 2. Forward to Crash Queue if crash detected
                    if crash_flag:
                        logging.warning(f"CRASH FLAG DETECTED for {helmet_id}!")
                        if CRASH_QUEUE_URL:
                            sqs.send_message(
                                QueueUrl=CRASH_QUEUE_URL,
                                MessageBody=msg['Body'] # Forward original raw string
                            )
                            logging.info(f"Forwarded crash event to crash-queue for {helmet_id}")

                    # 3. Delete message from Telemetry Queue
                    sqs.delete_message(
                        QueueUrl=TELEMETRY_QUEUE_URL,
                        ReceiptHandle=msg['ReceiptHandle']
                    )
                except Exception as e:
                    logging.error(f"Error processing message {msg.get('MessageId')}: {str(e)}")

        except Exception as e:
            logging.error(f"Error polling SQS: {str(e)}")
            time.sleep(5)

if __name__ == '__main__':
    logging.info("Starting Telemetry Processor Service...")
    process_messages()
