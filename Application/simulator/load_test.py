import os
import time
import json
import logging
import boto3
import urllib.request
from AWSIoTPythonSDK.MQTTLib import AWSIoTMQTTClient

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(message)s')

HELMET_ID = "HELMET-SIM-001"
IOT_ENDPOINT_URL = os.getenv("IOT_ENDPOINT_URL")
TELEMETRY_TOPIC = f"helmet/{HELMET_ID}/telemetry"

def download_certs():
    ssm = boto3.client('ssm', region_name='ap-south-1')
    
    if not os.path.exists("private.pem.key"):
        res_key = ssm.get_parameter(Name="/smart-helmet/simulator/private_key", WithDecryption=True)
        with open("private.pem.key", "w") as f:
            f.write(res_key['Parameter']['Value'])
            
    if not os.path.exists("certificate.pem.crt"):
        res_cert = ssm.get_parameter(Name="/smart-helmet/simulator/certificate_pem", WithDecryption=True)
        with open("certificate.pem.crt", "w") as f:
            f.write(res_cert['Parameter']['Value'])
            
    if not os.path.exists("AmazonRootCA1.pem"):
        urllib.request.urlretrieve("https://www.amazontrust.com/repository/AmazonRootCA1.pem", "AmazonRootCA1.pem")

def main():
    if not IOT_ENDPOINT_URL:
        logging.error("Please export IOT_ENDPOINT_URL before running.")
        return

    download_certs()

    myMQTTClient = AWSIoTMQTTClient("LOAD-TESTER-001")
    myMQTTClient.configureEndpoint(IOT_ENDPOINT_URL, 8883)
    myMQTTClient.configureCredentials("AmazonRootCA1.pem", "private.pem.key", "certificate.pem.crt")

    logging.info("Connecting to AWS IoT Core for Load Test...")
    myMQTTClient.connect()
    logging.info("Connected!")

    num_messages = 10000
    logging.info(f"Starting flood of {num_messages} messages...")

    for i in range(num_messages):
        payload = {
            "helmet_id": HELMET_ID,
            "timestamp": int(time.time() * 1000), # Milliseconds
            "accelerometer": {"x": 0.1, "y": 0.2, "z": 9.8},
            "speed": 45.0,
            "crash_flag": False,
            "location": "Latitude: 19.0760, Longitude: 72.8777",
            "load_test_msg_id": i
        }
        
        # QoS 0 (Fire and forget) to send them extremely fast without waiting for ACKs
        myMQTTClient.publish(TELEMETRY_TOPIC, json.dumps(payload), 0)
        
        if i % 100 == 0:
            logging.info(f"Sent {i} messages...")

    logging.info(f"Finished sending {num_messages} messages!")
    myMQTTClient.disconnect()

if __name__ == '__main__':
    main()
