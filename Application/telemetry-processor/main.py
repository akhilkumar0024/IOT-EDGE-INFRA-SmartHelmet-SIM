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
    
    global last_poll_time
    while not is_shutting_down:
        try:
            last_poll_time = time.time()
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
                    
                    if not helmet_id:
                        logging.warning(f"Invalid payload missing helmet_id: {body}")
                        sqs.delete_message(QueueUrl=TELEMETRY_QUEUE_URL, ReceiptHandle=msg['ReceiptHandle'])
                        continue

                    ttl_timestamp = int(time.time()) + (24 * 3600) # 24 hours TTL per design specification
                    items_to_write = []
                    crash_events = []

                    # Check if payload contains a telemetry array (batch mode)
                    if 'telemetry' in body and isinstance(body['telemetry'], list):
                        telemetry_list = body['telemetry']
                        for dp in telemetry_list:
                            ts = dp.get('timestamp') or body.get('batch_timestamp') or body.get('timestamp')
                            if ts is None:
                                continue
                            is_crash = bool(dp.get('crash_flag', False) or body.get('crash_flag', False))
                            speed = dp.get('speed', Decimal('0'))
                            accel = dp.get('accelerometer', {})
                            
                            items_to_write.append({
                                'helmetId': helmet_id,
                                'timestamp': Decimal(str(ts)),
                                'accelerometer': accel,
                                'speed': speed,
                                'crash_flag': is_crash,
                                'TimeToExist': ttl_timestamp
                            })
                            
                            if is_crash:
                                crash_events.append({
                                    'helmet_id': helmet_id,
                                    'timestamp': float(ts),
                                    'speed': float(speed),
                                    'location': dp.get('location', body.get('location', 'Unknown'))
                                })
                    else:
                        # Single item payload mode
                        ts = body.get('timestamp')
                        if ts is not None:
                            is_crash = bool(body.get('crash_flag', False))
                            speed = body.get('speed', Decimal('0'))
                            accel = body.get('accelerometer', {})
                            
                            items_to_write.append({
                                'helmetId': helmet_id,
                                'timestamp': Decimal(str(ts)),
                                'accelerometer': accel,
                                'speed': speed,
                                'crash_flag': is_crash,
                                'TimeToExist': ttl_timestamp
                            })
                            
                            if is_crash:
                                crash_events.append({
                                    'helmet_id': helmet_id,
                                    'timestamp': float(ts),
                                    'speed': float(speed),
                                    'location': body.get('location', 'Unknown')
                                })

                    # 1. Batch Write items to Hot Storage (DynamoDB)
                    if items_to_write:
                        with table.batch_writer() as batch:
                            for item in items_to_write:
                                batch.put_item(Item=item)
                        logging.info(f"Saved batch of {len(items_to_write)} telemetry records for {helmet_id}")

                    # 2. Forward crash events to Crash Queue
                    if crash_events and CRASH_QUEUE_URL:
                        for event in crash_events:
                            sqs.send_message(
                                QueueUrl=CRASH_QUEUE_URL,
                                MessageBody=json.dumps(event)
                            )
                            logging.warning(f"Forwarded crash event for {helmet_id} at timestamp {event['timestamp']} to crash-queue")

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
            # Check for zombie task (if the loop hasn't run in 5 minutes)
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
            
    # Suppress HTTP log messages to avoid log spam
    def log_message(self, format, *args):
        pass

def start_health_server():
    server = HTTPServer(('0.0.0.0', 8080), HealthCheckHandler)
    logging.info("Health check server listening on port 8080")
    server.serve_forever()

if __name__ == '__main__':
    logging.info("Starting Telemetry Processor Service...")
    
    # Start the health server in a background thread
    health_thread = threading.Thread(target=start_health_server, daemon=True)
    health_thread.start()
    
    process_messages()
