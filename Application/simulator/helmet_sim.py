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
    try:
        payload = json.loads(message.payload.decode('utf-8'))
        action = payload.get('action', 'UNKNOWN')
        msg_text = payload.get('message', '')
        
        print("\n" + "=" * 65)
        if action == "START_COUNTDOWN":
            print(f"🚨 HELMET HUD ALERT DISPLAYED! [{action}]")
            print(f"   Message : {msg_text}")
            print("   👉 Actions : Select Option 4 (Cancel) or Option 5 (FP_OVERRIDE)")
        elif action == "DISMISS":
            print(f"✅ HELMET HUD CLEARED! [{action}]")
            print(f"   Message : {msg_text}")
        else:
            print(f"📬 CLOUD STATUS NOTIFICATION: [{action}]")
            print(f"   Message : {msg_text}")
        print("=" * 65 + "\n")
    except Exception as e:
        logging.info(f"Received raw message on {message.topic}: {message.payload.decode('utf-8')}")

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
        now = int(time.time())
        num_points = 5 if crash_flag else 10
        start_ts = now - num_points + 1
        
        telemetry_points = []
        for i in range(num_points):
            ts = start_ts + i
            is_last_point_crash = (i == num_points - 1) and crash_flag
            telemetry_points.append({
                "timestamp": ts,
                "accelerometer": {"x": 8.5 if is_last_point_crash else 0.1, "y": 9.1 if is_last_point_crash else 0.2, "z": 12.0 if is_last_point_crash else 9.8},
                "speed": speed if not is_last_point_crash else (0.0 if speed > 10 else speed),
                "crash_flag": is_last_point_crash,
                "location": "Latitude: 19.0760, Longitude: 72.8777"
            })
            
        payload = {
            "helmet_id": HELMET_ID,
            "type": "crash_batch" if crash_flag else "no_crash_batch",
            "batch_timestamp": now,
            "telemetry": telemetry_points
        }
        myMQTTClient.publish(TELEMETRY_TOPIC, json.dumps(payload), 1)
        logging.info(f"Sent Telemetry Batch ({payload['type']}) -> Points: {len(telemetry_points)} | Speed: {speed} mph | Crash: {crash_flag}")

    def send_override(action="cancel"):
        payload = {
            "helmet_id": HELMET_ID,
            "action": action,
            "timestamp": int(time.time())
        }
        myMQTTClient.publish(OVERRIDE_TOPIC, json.dumps(payload), 1)
        logging.info(f"Sent Override -> Action: {action}")

    try:
        while True:
            print("\n--- SIMULATOR CONTROLS ---")
            print("1. Send Normal Riding Data (10 datapoints, Speed: 45 mph)")
            print("2. Send Crash Event (5 datapoints, High Speed, crash_flag=True)")
            print("3. Send False Positive (5 datapoints, Low Speed, crash_flag=True)")
            print("4. Press Cancel Button (action: cancel)")
            print("5. Press False Positive Override Button (action: FP_OVERRIDE)")
            print("6. Exit")
            
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
                send_override("cancel")
            elif choice == '5':
                send_override("FP_OVERRIDE")
            elif choice == '6':
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
