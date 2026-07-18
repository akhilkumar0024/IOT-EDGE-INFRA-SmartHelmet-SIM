# Smart Helmet Infrastructure — Finalized Design Flows

This document records the verified event-driven workflows for the Smart Helmet edge-to-cloud infrastructure. 

---

## Scenario 1: Standard Alert Sequence

### Scenario 1A: Standard Alert and Cancel Arrive On Time

#### 1. Happy Path (No Cancellation)
* **T0 (Detection):** ECS Alert Instance retrieves a genuine standard crash event from the SQS Alert Queue:
  `{ "helmet_id": "001", "alert_type": "STD_CD", "timestamp": ts1 }`
* **T2 (Initiation):** 
  * ECS Alert Instance triggers **Step Function 1 (SFN1)** and gets its execution ARN (`SFN1_ARN`).
  * SFN1 enters a `Wait` state for 30 seconds.
  * ECS writes the active lease to the Device Status Table (`smart-helmet-device-status`):
    `{ "helmetId": "001", "timestamp": ts1, "status": "STD_CD", "sfnExecutionArn": "SFN1_ARN" }`
  * ECS publishes a `START_COUNTDOWN` message to the IoT Core topic to display the 30-second warning on the helmet HUD.
* **T32 (Alert Expiry):** SFN1 completes its 30-second wait:
  * Reads the status of `001` from the Device Status Table.
  * Verifies that the table's `sfnExecutionArn` matches its own execution ARN (`SFN1_ARN`).
  * Triggers the SNS Alert (email notification to emergency services/next of kin).
  * Logs the incident to DynamoDB Cold Storage: `{ "helmetId": "001", "status": "INCIDENT_CONFIRMED", "timestamp": ts1 }`
  * Deletes the registry row from the Device Status Table.

---

#### 2. Cancellation Path (User Aborts Alert on Time)
* **T0 - T2:** Same as the Happy Path. Registry shows `{ "status": "STD_CD", "sfnExecutionArn": "SFN1_ARN" }`. SFN1 is waiting.
* **T5 (Rider Cancel):** Rider taps "Cancel" on their helmet/app. The local HUD clears itself. IoT Core routes the cancel message to the SQS Override Queue:
  `{ "helmet_id": "001", "action": "CANCEL", "timestamp": ts2 }`
* **T6 (Fargate Processing):** ECS Alert Instance polls the Override Queue, reads the cancel message, and looks up `001` in the Device Status Table.
* **T7 (State Update):** ECS updates the status row to:
  `{ "helmetId": "001", "timestamp": ts2, "status": "CANCEL", "sfnExecutionArn": "SFN1_ARN" }`
* **T32 (Evaluation):** SFN1 completes its 30-second wait:
  * Reads the status of `001` from the Device Status Table.
  * Identifies the status is `CANCEL`.
  * Verifies that the table's `sfnExecutionArn` matches its own execution ARN (`SFN1_ARN`).
  * Writes a cancellation log to DynamoDB Cold Storage: `{ "helmetId": "001", "status": "INCIDENT_CANCELLED", "timestamp": ts2 }`
  * Deletes the registry row from the Device Status Table and terminates cleanly.

---

### Scenario 1B: Standard Alert Cancel Arrives Late (State Reconciliation)

* **T0 - T2:** Same as Scenario 1A. SFN1 is waiting. Registry is `{ "status": "STD_CD", "sfnExecutionArn": "SFN1_ARN" }`.
* **T5 (Rider Cancel):** Rider taps "Cancel" on their helmet/app. The local HUD clears itself. IoT Core routes the cancel message to SQS Override Queue:
  `{ "helmet_id": "001", "action": "CANCEL", "timestamp": ts2 }`
* **T32 (Alert Expiry & Execution):** SFN1 completes its 30-second wait:
  * Reads the status of `001` from the Device Status Table.
  * Sees the status is still `STD_CD` (as the cancel message is delayed in the SQS queue and has not been read by ECS yet due to queue lag).
  * Verifies the ARN matches `SFN1_ARN`.
  * Triggers the SNS Emergency Alert to emergency services.
  * Logs the incident to DynamoDB Cold Storage: `{ "helmetId": "001", "status": "INCIDENT_CONFIRMED", "timestamp": ts1 }`
  * Deletes the registry row from the Device Status Table and exits.
* **T35 (Late Message Delivery):** The ECS Alert Instance finally reads the late cancel message `{ "helmet_id": "001", "action": "CANCEL", "timestamp": ts2 }` from the Override Queue.
* **T36 (Reconciliation Trigger):** 
  * ECS queries the Device Status Table for `001`. It finds the row is **missing** (indicating the timer already expired and SFN1 triggered the emergency alerts).
  * ECS triggers the reconciliation workflow by starting **Step Function 2 (SFN2)**.
  * ECS writes the active reconciliation lease to the Device Status Table:
    `{ "helmetId": "001", "timestamp": ts2, "status": "CANCEL", "sfnExecutionArn": "SFN2_ARN" }`
* **T37 (Reconciliation Execution):** SFN2 runs:
  * Reads the status of `001` from the Device Status Table.
  * Verifies the `sfnExecutionArn` matches `SFN2_ARN`.
  * Deletes the registry row from the Device Status Table to clean up.
  * Queries the latest record for `001` with status `INCIDENT_CONFIRMED` from DynamoDB Cold Storage to find `ts1`.
  * Calculates the cancellation delay: `ts2 - ts1` (Rider Intent Check) and the current elapsed time: `t_now - ts1` (Real-Time Safety Check, where `t_now` is the current server time).
  * **Evaluation:**
    * **If `ts2 - ts1 < 30 seconds` AND `t_now - ts1 < 300 seconds` (5 minutes):** The rider clicked cancel during their local warning window, and the message arrived in the cloud within a safe 5-minute reconciliation window. SFN2 triggers the follow-up Stand-Down SNS notification to emergency services and updates Cold Storage to `RESOLVED_BY_LATE_CANCEL`.
    * **If `ts2 - ts1 >= 30 seconds` OR `t_now - ts1 >= 300 seconds`:** The cancellation was clicked too late, or the message was delayed too long in the network (e.g. offline buffering). SFN2 exits silently without sending a Stand-Down alert, keeping emergency services dispatched.

---

## Scenario 2: False Positive / Override Sequence

### Scenario 2A: False Positive Alert and Override Arrives On Time

#### 1. Happy Path (Rider Does Not Click Override - Silent Dismissal)
* **T0 (Detection):** ECS Alert Instance retrieves a false positive crash event from the SQS Alert Queue:
  `{ "helmet_id": "001", "alert_type": "FP_CD", "timestamp": ts1 }`
* **T1 (Initiation):** 
  * ECS Alert Instance triggers **Step Function 3 (SFN3)** and gets its execution ARN (`SFN3_ARN`).
  * SFN3 enters a `Wait` state for 10 seconds.
  * ECS writes the active lease to the Device Status Table:
    `{ "helmetId": "001", "timestamp": ts1, "status": "FP_CD", "sfnExecutionArn": "SFN3_ARN" }`
  * ECS publishes a `START_COUNTDOWN` message to the IoT Core topic to display the 10-second warning on the helmet HUD.
* **T11 (Alert Expiry):** SFN3 completes its 10-second wait:
  * Reads the status of `001` from the Device Status Table.
  * Sees the status is still `FP_CD` (as the rider did nothing).
  * Verifies the table's `sfnExecutionArn` matches `SFN3_ARN`.
  * Logs the silent dismissal to DynamoDB Cold Storage: `{ "helmetId": "001", "status": "FALSE_POSITIVE_DISMISSED", "timestamp": ts1 }`
  * Deletes the registry row from the Device Status Table and terminates cleanly.

---

#### 2. Override Path (Rider Overrides Warning on Time)
* **T0 - T1:** Same as the Happy Path. SFN3 is waiting. Registry shows `{ "status": "FP_CD", "sfnExecutionArn": "SFN3_ARN" }`.
* **T4 (Rider Override):** Rider taps "Override" on their helmet/app. The helmet publishes the override message, which IoT Core routes to the SQS Override Queue:
  `{ "helmet_id": "001", "action": "FP_OVERRIDE", "timestamp": ts2 }`
* **T5 (Fargate Processing):** 
  * ECS Alert Instance reads the override message.
  * Since the message has `FP_OVERRIDE`, ECS immediately triggers a new **Step Function 1 (SFN1)** for the 30-second countdown and gets `SFN1_ARN`.
  * ECS upserts (`PutItem`) the registry row for `001` to:
    `{ "helmetId": "001", "timestamp": ts2, "status": "STD_CD", "sfnExecutionArn": "SFN1_ARN" }`
  * ECS publishes a `START_COUNTDOWN` (30s) message to the IoT Core topic, which triggers the 30-second warning countdown on the helmet HUD. SFN1 is now waiting.
* **T11 (SFN3 Expiry):** SFN3 completes its 10-second wait:
  * Reads the status of `001` from the Device Status Table.
  * Sees `sfnExecutionArn` is `SFN1_ARN` and `status` is `STD_CD`.
  * Identifies that the ARNs do not match (`SFN3_ARN` $\neq$ `SFN1_ARN`).
  * **SFN3 terminates silently** without writing to Cold Storage and without deleting the row.
* **SFN1 Evaluation:** SFN1 will run to completion and evaluate status after 30 seconds as described in Scenario 1.

---

### Scenario 2B: False Positive Override Arrives Late (Fail-Safe Recovery)

* **T0 - T1:** Same as Scenario 2A. SFN3 is waiting. Registry shows `{ "status": "FP_CD", "sfnExecutionArn": "SFN3_ARN" }`.
* **T4 (Rider Override):** Rider taps "Override" on their helmet/app. The helmet publishes the override message, which IoT Core routes to the SQS Override Queue:
  `{ "helmet_id": "001", "action": "FP_OVERRIDE", "timestamp": ts2 }`
* **T11 (SFN3 Expiry):** SFN3 completes its 10-second wait:
  * Reads the status of `001` from the Device Status Table.
  * Sees the status is still `FP_CD` (as the override message has not been read by ECS yet due to queue lag).
  * Verifies the ARN matches `SFN3_ARN`.
  * Logs the silent dismissal to DynamoDB Cold Storage: `{ "helmetId": "001", "status": "FALSE_POSITIVE_DISMISSED", "timestamp": ts1 }`
  * Deletes the registry row from the Device Status Table and terminates cleanly.
* **T12 (Late Message Delivery):** The ECS Alert Instance finally reads the late override message `{ "helmet_id": "001", "action": "FP_OVERRIDE", "timestamp": ts2 }` from the Override Queue.
* **T13 (Fargate Processing & Fail-Safe Trigger):**
  * Since the message has `FP_OVERRIDE`, ECS immediately triggers a new **Step Function 1 (SFN1)** for the 30-second countdown and gets `SFN1_ARN` (the fact that the registry row is missing is ignored).
  * ECS upserts (`PutItem`) the registry row for `001` to:
    `{ "helmetId": "001", "timestamp": ts2, "status": "STD_CD", "sfnExecutionArn": "SFN1_ARN" }`
  * ECS publishes a `START_COUNTDOWN` (30s) message to the IoT Core topic, triggering the 30-second warning countdown on the helmet HUD.
* **SFN1 Evaluation:** SFN1 waits for 30 seconds and runs its standard evaluation. If the user doesn't cancel, it alerts emergency services and logs `INCIDENT_CONFIRMED` to Cold Storage.
