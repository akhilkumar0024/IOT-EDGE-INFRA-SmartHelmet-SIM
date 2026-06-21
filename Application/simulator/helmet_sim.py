import os
import time
import json
import logging
import threading
import boto3
import urllib.request
from AWSIoTPythonSDK.MQTTLib import AWSIoTMQTTClient

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(message)s')

HELMET_ID = "HELMET-SIM-001"
IOT_ENDPOINT_URL = os.getenv("IOT_ENDPOINT_URL")

# Define Topics
TELEMETRY_TOPIC = f"helmet/{HELMET_ID}/telemetry"
OVERRIDE_TOPIC = f"helmet/{HELMET_ID}/alert/override"
LWT_TOPIC = f"helmet/{HELMET_ID}/lwt"
STATUS_TOPIC = f"helmet/{HELMET_ID}/alert/status"

def download_certs():
    logging.info("Fetching IoT Certificates from SSM Parameter Store...")
    ssm = boto3.client('ssm', region_name='ap-south-1')
    
    # Fetch Private Key
    res_key = ssm.get_parameter(Name="/smart-helmet/simulator/private_key", WithDecryption=True)
    with open("private.pem.key", "w") as f:
        f.write(res_key['Parameter']['Value'])
        
    # Fetch Certificate
    res_cert = ssm.get_parameter(Name="/smart-helmet/simulator/certificate_pem", WithDecryption=True)
    with open("certificate.pem.crt", "w") as f:
        f.write(res_cert['Parameter']['Value'])
        
    # Download AWS Root CA
    if not os.path.exists("AmazonRootCA1.pem"):
        logging.info("Downloading AWS Root CA...")
        urllib.request.urlretrieve("https://www.amazontrust.com/repository/AmazonRootCA1.pem", "AmazonRootCA1.pem")

def custom_callback(client, userdata, message):
    logging.info("\n=============================================")
    logging.info(f"📬 MESSAGE RECEIVED FROM CLOUD: {message.topic}")
    logging.info(f"Payload: {message.payload.decode('utf-8')}")
    logging.info("=============================================\n")

def main():
    if not IOT_ENDPOINT_URL:
        logging.error("Please export IOT_ENDPOINT_URL before running.")
        return

    download_certs()

    # Init AWSIoTMQTTClient
    myMQTTClient = AWSIoTMQTTClient(HELMET_ID)
    myMQTTClient.configureEndpoint(IOT_ENDPOINT_URL, 8883)
    myMQTTClient.configureCredentials("AmazonRootCA1.pem", "private.pem.key", "certificate.pem.crt")

    # Configure LWT (Last Will and Testament)
    lwt_payload = json.dumps({"helmet_id": HELMET_ID, "status": "offline", "timestamp": int(time.time())})
    myMQTTClient.configureLastWill(LWT_TOPIC, lwt_payload, 1)

    logging.info("Connecting to AWS IoT Core...")
    myMQTTClient.connect()
    logging.info("Connected!")

    # Subscribe to status topic
    myMQTTClient.subscribe(STATUS_TOPIC, 1, custom_callback)
    logging.info(f"Subscribed to {STATUS_TOPIC}")

    def send_telemetry(speed, crash_flag):
        payload = {
            "helmet_id": HELMET_ID,
            "timestamp": int(time.time()),
            "accelerometer": {"x": 0.1, "y": 0.2, "z": 9.8},
            "speed": speed,
            "crash_flag": crash_flag,
            "location": "Latitude: 19.0760, Longitude: 72.8777"
        }
        myMQTTClient.publish(TELEMETRY_TOPIC, json.dumps(payload), 1)
        logging.info(f"Sent Telemetry -> Speed: {speed} mph | Crash: {crash_flag}")

    def send_override():
        payload = {
            "helmet_id": HELMET_ID,
            "action": "cancel",
            "timestamp": int(time.time())
        }
        myMQTTClient.publish(OVERRIDE_TOPIC, json.dumps(payload), 1)
        logging.info(f"Sent Override -> Cancel Signal")

    try:
        while True:
            print("\n--- SIMULATOR CONTROLS ---")
            print("1. Send Normal Riding Data (Speed: 45 mph)")
            print("2. Send Crash Event (High Speed, crash_flag=True)")
            print("3. Send False Positive (Low Speed, crash_flag=True)")
            print("4. Press Cancel/Override Button")
            print("5. Exit")
            
            choice = input("Select an option: ")
            
            if choice == '1':
                send_telemetry(45.0, False)
            elif choice == '2':
                send_telemetry(65.5, True)
                print("Crash simulated! Waiting for countdown from cloud...")
            elif choice == '3':
                send_telemetry(5.0, True)
                print("Helmet dropped! Simulating false positive. Waiting for cloud...")
            elif choice == '4':
                send_override()
            elif choice == '5':
                break
            else:
                print("Invalid choice.")
                
            time.sleep(1)

    except KeyboardInterrupt:
        pass

    logging.info("Disconnecting...")
    myMQTTClient.disconnect()

if __name__ == '__main__':
    main()
