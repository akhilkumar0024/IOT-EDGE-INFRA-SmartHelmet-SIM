import os
import json
import time
import logging
import boto3
from decimal import Decimal

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

CRASH_QUEUE_URL = os.getenv('CRASH_QUEUE_URL')
ALERT_QUEUE_URL = os.getenv('ALERT_QUEUE_URL')
HOT_STORAGE_NAME = os.getenv('HOT_STORAGE_NAME')

sqs = boto3.client('sqs', region_name='ap-south-1')
dynamodb = boto3.resource('dynamodb', region_name='ap-south-1')

def process_messages():
    if not CRASH_QUEUE_URL or not ALERT_QUEUE_URL or not HOT_STORAGE_NAME:
        logging.error("Missing required environment variables.")
        return

    while True:
        try:
            response = sqs.receive_message(
                QueueUrl=CRASH_QUEUE_URL,
                MaxNumberOfMessages=10,
                WaitTimeSeconds=10
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

        except Exception as e:
            logging.error(f"Error polling Crash Queue: {str(e)}")
            time.sleep(5)

if __name__ == '__main__':
    logging.info("Starting Processing Engine Service...")
    process_messages()
