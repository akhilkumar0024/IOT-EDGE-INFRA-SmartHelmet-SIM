import json
import logging
import os
import signal
import threading
import time
import uuid
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


def countdown_status(alert_type):
    return 'FP_CD' if alert_type == 'FP_CD' else 'STD_CD'


def acquire_lease(helmet_id, incident_id, incident_timestamp, alert_type, expected_owner_id=None):
    registry = dynamodb.Table(EXECUTION_REGISTRY_NAME)
    wait_seconds, message = get_countdown(alert_type)
    countdown = countdown_status(alert_type)
    deadline = int(time.time()) + wait_seconds
    item = {
        'helmetId': helmet_id,
        'ownerIncidentId': incident_id,
        'status': 'INITIALIZING',
        'countdownStatus': countdown,
        'alertType': alert_type,
        'incidentTimestamp': Decimal(str(incident_timestamp)),
        'serverDeadline': deadline,
        'TimeToExist': deadline + 86400,
    }
    current = registry.get_item(Key={'helmetId': helmet_id}).get('Item')

    if current and current.get('ownerIncidentId') == incident_id:
        if current.get('status') != 'INITIALIZING':
            return None
        return wait_seconds, message, countdown

    if expected_owner_id:
        if not current or current.get('ownerIncidentId') != expected_owner_id or current.get('status') != 'FP_CD':
            logging.info('False-positive override no longer owns the active lease for %s', helmet_id)
            return None
        condition = 'ownerIncidentId = :expected_owner AND #status = :expected_status'
        values = {
            ':expected_owner': expected_owner_id,
            ':expected_status': 'FP_CD',
        }
    elif current:
        current_timestamp = float(current.get('incidentTimestamp', 0))
        if current_timestamp >= float(incident_timestamp):
            logging.info('Ignoring stale or duplicate incident %s for %s', incident_id, helmet_id)
            return None
        condition = 'ownerIncidentId = :expected_owner AND incidentTimestamp = :expected_timestamp'
        values = {
            ':expected_owner': current['ownerIncidentId'],
            ':expected_timestamp': current['incidentTimestamp'],
        }
    else:
        condition = 'attribute_not_exists(helmetId)'
        values = {}

    try:
        put_request = {
            'Item': item,
            'ConditionExpression': condition,
        }
        if expected_owner_id:
            put_request['ExpressionAttributeNames'] = {'#status': 'status'}
        if values:
            put_request['ExpressionAttributeValues'] = values
        registry.put_item(**put_request)
    except ClientError as error:
        if not is_conditional_failure(error):
            raise
        latest = registry.get_item(Key={'helmetId': helmet_id}).get('Item')
        if latest and latest.get('ownerIncidentId') == incident_id:
            return None if latest.get('status') != 'INITIALIZING' else (wait_seconds, message, countdown)
        logging.info('Incident %s did not acquire the active lease for %s', incident_id, helmet_id)
        return None

    return wait_seconds, message, countdown


def start_incident(helmet_id, incident_id, incident_timestamp, alert_type, expected_owner_id=None):
    lease = acquire_lease(
        helmet_id,
        incident_id,
        incident_timestamp,
        alert_type,
        expected_owner_id,
    )
    if not lease:
        return True

    wait_seconds, message, countdown = lease
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

    registry = dynamodb.Table(EXECUTION_REGISTRY_NAME)
    try:
        registry.update_item(
            Key={'helmetId': helmet_id},
            UpdateExpression='SET #status = :countdown, executionArn = :execution_arn',
            ConditionExpression='ownerIncidentId = :incident_id AND #status = :initializing',
            ExpressionAttributeNames={'#status': 'status'},
            ExpressionAttributeValues={
                ':countdown': countdown,
                ':execution_arn': execution['executionArn'],
                ':incident_id': incident_id,
                ':initializing': 'INITIALIZING',
            },
        )
    except ClientError as error:
        if not is_conditional_failure(error):
            raise
        logging.info('Incident %s lost its lease before its workflow became active', incident_id)
        return True

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
    active = registry.get_item(Key={'helmetId': helmet_id}).get('Item')
    if (
        active
        and active.get('ownerIncidentId') == incident_id
        and active.get('status') in {'INITIALIZING', 'STD_CD', 'FP_CD'}
        and now <= int(active['serverDeadline'])
    ):
        try:
            registry.update_item(
                Key={'helmetId': helmet_id},
                UpdateExpression='SET #status = :cancelled',
                ConditionExpression='ownerIncidentId = :incident_id AND #status IN (:initializing, :standard, :false_positive) AND serverDeadline >= :now',
                ExpressionAttributeNames={'#status': 'status'},
                ExpressionAttributeValues={
                    ':cancelled': 'CANCELLED',
                    ':incident_id': incident_id,
                    ':initializing': 'INITIALIZING',
                    ':standard': 'STD_CD',
                    ':false_positive': 'FP_CD',
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
        active = registry.get_item(Key={'helmetId': helmet_id}).get('Item')

        # Case A: Active FP lease still exists -> ownership-fenced in-place upgrade.
        # An override arriving before the FP window expires upgrades to STD without
        # releasing the lease to another actor.
        if active and active.get('ownerIncidentId') == incident_id:
            return start_incident(
                helmet_id,
                str(uuid.uuid5(uuid.NAMESPACE_URL, f'{incident_id}:FP_OVERRIDE')),
                active['incidentTimestamp'],
                'STD_CD',
                expected_owner_id=incident_id,
            )

        # Case B: FP lease already released (the FP window expired before this
        # message was dequeued). Fail-safe (Alert_Infra_design.md Scenario 2B):
        # never silently drop the rider's request for help — start a fresh standard
        # countdown. Only skip if a DIFFERENT incident currently holds the lease.
        if not (active and active.get('ownerIncidentId') != incident_id):
            incident_timestamp = body.get('incident_timestamp')
            if incident_timestamp is not None:
                return start_incident(
                    helmet_id,
                    str(uuid.uuid5(uuid.NAMESPACE_URL, f'{incident_id}:FP_OVERRIDE')),
                    incident_timestamp,
                    'STD_CD',
                    expected_owner_id=None,
                )
            logging.warning('Late FP_OVERRIDE missing incident_timestamp for %s', helmet_id)
        else:
            logging.warning(
                'FP_OVERRIDE ignored - lease currently held by another incident for %s',
                helmet_id,
            )
        return True
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
