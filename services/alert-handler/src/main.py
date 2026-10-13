import json
import logging
import os
import signal
import threading
import time
from decimal import Decimal
from http.server import BaseHTTPRequestHandler, HTTPServer

import boto3
from botocore.exceptions import ClientError

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

ALERT_QUEUE_URL = os.getenv('ALERT_QUEUE_URL')
OVERRIDE_QUEUE_URL = os.getenv('OVERRIDE_QUEUE_URL')
EXECUTION_REGISTRY_NAME = os.getenv('EXECUTION_REGISTRY_NAME')
COLD_STORAGE_NAME = os.getenv('COLD_STORAGE_NAME')
STEP_FUNCTION_ARN = os.getenv('STEP_FUNCTION_ARN')
RECONCILIATION_STEP_FUNCTION_ARN = os.getenv('RECONCILIATION_STEP_FUNCTION_ARN')
IOT_ENDPOINT_URL = os.getenv('IOT_ENDPOINT_URL')
AWS_REGION = os.getenv('AWS_REGION', 'ap-south-1')

sqs = boto3.client('sqs', region_name=AWS_REGION)
dynamodb = boto3.resource('dynamodb', region_name=AWS_REGION)
sfn = boto3.client('stepfunctions', region_name=AWS_REGION)
ssm = boto3.client('ssm', region_name=AWS_REGION)
iot_data = boto3.client(
    'iot-data',
    region_name=AWS_REGION,
    **({'endpoint_url': f'https://{IOT_ENDPOINT_URL}'} if IOT_ENDPOINT_URL else {})
)


def publish_to_helmet(helmet_id, action, message, incident_id=None, incident_timestamp=None):
    payload = {
        'action': action,
        'message': message,
        'timestamp': int(time.time()),
        'incident_id': incident_id,
        'incident_timestamp': incident_timestamp,
    }
    iot_data.publish(
        topic=f'helmet/{helmet_id}/alert/status',
        qos=1,
        payload=json.dumps(payload),
    )


def get_ssm_parameter(name, default_value):
    try:
        return int(ssm.get_parameter(Name=name)['Parameter']['Value'])
    except ClientError as error:
        logging.warning('Using default for %s: %s', name, error)
        return default_value


def is_conditional_failure(error):
    return error.response['Error']['Code'] == 'ConditionalCheckFailedException'


def get_countdown(alert_type):
    if alert_type == 'FP_CD':
        return get_ssm_parameter('/smart-helmet/config/false_positive_window_seconds', 5), 'False positive detected.'
    if alert_type == 'retrospective':
        return get_ssm_parameter('/smart-helmet/config/retrospective_alert_window_seconds', 300), 'Retrospective crash detected.'
    return get_ssm_parameter('/smart-helmet/config/standard_alert_window_seconds', 30), 'Crash detected.'


def start_incident(helmet_id, incident_id, incident_timestamp, alert_type):
    registry = dynamodb.Table(EXECUTION_REGISTRY_NAME)
    wait_seconds, message = get_countdown(alert_type)
    deadline = int(time.time()) + wait_seconds
    item = {
        'helmetId': helmet_id,
        'incidentId': incident_id,
        'status': 'INITIALIZING',
        'alertType': alert_type,
        'incidentTimestamp': Decimal(str(incident_timestamp)),
        'serverDeadline': deadline,
        'TimeToExist': deadline + 86400,
    }

    try:
        registry.put_item(
            Item=item,
            ConditionExpression='attribute_not_exists(helmetId) AND attribute_not_exists(incidentId)',
        )
    except ClientError as error:
        if not is_conditional_failure(error):
            raise
        existing = registry.get_item(Key={'helmetId': helmet_id, 'incidentId': incident_id}).get('Item')
        if existing and existing.get('status') in {'COUNTDOWN_ACTIVE', 'CANCELLED', 'CONFIRMED', 'RESOLVED'}:
            return True
        if not existing or existing.get('status') != 'INITIALIZING':
            raise

    execution_input = {
        'helmet_id': helmet_id,
        'incident_id': incident_id,
        'incident_timestamp': float(incident_timestamp),
        'wait_seconds': wait_seconds,
    }
    try:
        execution = sfn.start_execution(
            stateMachineArn=STEP_FUNCTION_ARN,
            name=incident_id,
            input=json.dumps(execution_input),
        )
    except sfn.exceptions.ExecutionAlreadyExists:
        logging.info('Execution already exists for incident %s', incident_id)
        return True

    registry.update_item(
        Key={'helmetId': helmet_id, 'incidentId': incident_id},
        UpdateExpression='SET #status = :active, executionArn = :execution_arn',
        ConditionExpression='#status = :initializing',
        ExpressionAttributeNames={'#status': 'status'},
        ExpressionAttributeValues={
            ':active': 'COUNTDOWN_ACTIVE',
            ':initializing': 'INITIALIZING',
            ':execution_arn': execution['executionArn'],
        },
    )
    publish_to_helmet(
        helmet_id,
        'START_COUNTDOWN',
        f'{message} Countdown: {wait_seconds}s',
        incident_id,
        float(incident_timestamp),
    )
    return True


def handle_alert(message):
    body = json.loads(message['Body'])
    helmet_id = body.get('helmet_id')
    incident_id = body.get('incident_id')
    incident_timestamp = body.get('timestamp')
    if not helmet_id or not incident_id or incident_timestamp is None:
        logging.warning('Malformed alert message: %s', body)
        return True
    return start_incident(helmet_id, incident_id, incident_timestamp, body.get('alert_type', 'STD_CD'))


def handle_cancel(helmet_id, incident_id, incident_timestamp):
    if not incident_id or incident_timestamp is None:
        logging.warning('Cancellation requires incident_id and incident_timestamp for %s', helmet_id)
        return True

    registry = dynamodb.Table(EXECUTION_REGISTRY_NAME)
    now = int(time.time())
    active = registry.get_item(Key={'helmetId': helmet_id, 'incidentId': incident_id}).get('Item')
    if active and active.get('status') == 'COUNTDOWN_ACTIVE' and now <= int(active['serverDeadline']):
        try:
            registry.update_item(
                Key={'helmetId': helmet_id, 'incidentId': incident_id},
                UpdateExpression='SET #status = :cancelled',
                ConditionExpression='#status = :active AND serverDeadline >= :now',
                ExpressionAttributeNames={'#status': 'status'},
                ExpressionAttributeValues={
                    ':cancelled': 'CANCELLED',
                    ':active': 'COUNTDOWN_ACTIVE',
                    ':now': now,
                },
            )
            publish_to_helmet(helmet_id, 'DISMISS', 'Alert cancelled successfully.', incident_id, incident_timestamp)
            return True
        except ClientError as error:
            if not is_conditional_failure(error):
                raise

    cold_storage = dynamodb.Table(COLD_STORAGE_NAME)
    incident = cold_storage.get_item(
        Key={'helmetId': helmet_id, 'timestamp': Decimal(str(incident_timestamp))}
    ).get('Item')
    if not incident or incident.get('incidentId') != incident_id:
        logging.warning('No matching confirmed incident for late cancellation: %s', incident_id)
        return True

    reconciliation_input = {
        'helmet_id': helmet_id,
        'incident_id': incident_id,
        'incident_timestamp': float(incident_timestamp),
        'is_reconcilable': 0 <= now - float(incident_timestamp) <= 300,
    }
    try:
        sfn.start_execution(
            stateMachineArn=RECONCILIATION_STEP_FUNCTION_ARN,
            name=f'reconcile-{incident_id}',
            input=json.dumps(reconciliation_input),
        )
    except sfn.exceptions.ExecutionAlreadyExists:
        logging.info('Reconciliation already exists for %s', incident_id)
    return True


def handle_override(message):
    body = json.loads(message['Body'])
    helmet_id = body.get('helmet_id')
    incident_id = body.get('incident_id')
    if not helmet_id:
        logging.warning('Malformed override message: %s', body)
        return True
    action = body.get('action', '').upper()
    if action == 'CANCEL':
        return handle_cancel(helmet_id, incident_id, body.get('incident_timestamp'))
    if action == 'FP_OVERRIDE':
        if not incident_id:
            logging.warning('False-positive override requires incident_id for %s', helmet_id)
            return True
        registry = dynamodb.Table(EXECUTION_REGISTRY_NAME)
        active = registry.get_item(Key={'helmetId': helmet_id, 'incidentId': incident_id}).get('Item')
        if not active:
            logging.warning('No active false-positive incident found for %s', incident_id)
            return True
        try:
            registry.update_item(
                Key={'helmetId': helmet_id, 'incidentId': incident_id},
                UpdateExpression='SET #status = :superseded',
                ConditionExpression='#status = :active AND alertType = :false_positive',
                ExpressionAttributeNames={'#status': 'status'},
                ExpressionAttributeValues={
                    ':superseded': 'SUPERSEDED',
                    ':active': 'COUNTDOWN_ACTIVE',
                    ':false_positive': 'FP_CD',
                },
            )
        except ClientError as error:
            if is_conditional_failure(error):
                logging.info('False-positive override already handled for %s', incident_id)
                return True
            raise
        return start_incident(
            helmet_id,
            f'{incident_id}-override',
            active['incidentTimestamp'],
            'STD_CD',
        )
    logging.warning('Unsupported override action: %s', body.get('action'))
    return True


def process_queue(queue_url, handler):
    response = sqs.receive_message(QueueUrl=queue_url, MaxNumberOfMessages=5, WaitTimeSeconds=10)
    for message in response.get('Messages', []):
        try:
            if handler(message):
                sqs.delete_message(QueueUrl=queue_url, ReceiptHandle=message['ReceiptHandle'])
        except Exception:
            logging.exception('Message processing failed; leaving message for retry')


is_shutting_down = False
last_poll_time = time.time()


def sigterm_handler(signum, frame):
    global is_shutting_down
    is_shutting_down = True


class HealthCheckHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200 if time.time() - last_poll_time <= 300 else 500)
        self.end_headers()

    def log_message(self, format, *args):
        pass


def start_health_server():
    HTTPServer(('0.0.0.0', 8080), HealthCheckHandler).serve_forever()


def process_messages():
    global last_poll_time
    if not all([ALERT_QUEUE_URL, OVERRIDE_QUEUE_URL, EXECUTION_REGISTRY_NAME, COLD_STORAGE_NAME, STEP_FUNCTION_ARN, RECONCILIATION_STEP_FUNCTION_ARN]):
        raise RuntimeError('Missing required environment variables')
    while not is_shutting_down:
        last_poll_time = time.time()
        process_queue(ALERT_QUEUE_URL, handle_alert)
        process_queue(OVERRIDE_QUEUE_URL, handle_override)


if __name__ == '__main__':
    signal.signal(signal.SIGTERM, sigterm_handler)
    signal.signal(signal.SIGINT, sigterm_handler)
    threading.Thread(target=start_health_server, daemon=True).start()
    process_messages()
