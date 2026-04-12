# Smart Helmet — Data Flow Documentation

---

## Table of Contents

- [Flow 1 — Startup Sequence (Happy Path)](#flow-1--startup-sequence-happy-path)
- [Flow 2 — Startup Sequence Sad Paths](#flow-2--startup-sequence-sad-paths)
- [Flow 3 — Crash Detection and Alert Flow](#flow-3--crash-detection-and-alert-flow)
- [Flow 4 — Phone Dead During Crash](#flow-4--phone-dead-during-crash)
- [Flow 5 — Retrospective Alert After Phone Revival](#flow-5--retrospective-alert-after-phone-revival)
- [Flow 6 — Graceful Shutdown](#flow-6--graceful-shutdown)
- [Flow 7 — Battery Death](#flow-7--battery-death)
- [Flow 8 — Unexpected Dropout / LWT](#flow-8--unexpected-dropout--lwt)
- [Flow 9 — Mass Alert and Infrastructure Failure Detection](#flow-9--mass-alert-and-infrastructure-failure-detection)
    - [9A — Monitoring Stack and Detection](#flow-9a--monitoring-stack-and-detection)
    - [9B — Sensor Failure (Device Layer)](#flow-9b--sensor-failure-device-layer)
    - [9C — Helmet Telemetry to Smartphone Failure (Device Layer)](#flow-9c--helmet-telemetry-to-smartphone-failure-device-layer)
    - [9D — Smartphone Telemetry to Cloud Failure (Device Layer)](#flow-9d--smartphone-telemetry-to-cloud-failure-device-layer)
    - [9E — IoT Core / MQTT Broker Failure (Cloud Layer)](#flow-9e--iot-core--mqtt-broker-failure-cloud-layer)
    - [9F — Telemetry Infrastructure Failure (Cloud Layer)](#flow-9f--telemetry-infrastructure-failure-cloud-layer)
    - [9G — Processing Infrastructure Failure (Cloud Layer)](#flow-9g--processing-infrastructure-failure-cloud-layer)
    - [9H — Alerting Infrastructure Failure (Cloud Layer)](#flow-9h--alerting-infrastructure-failure-cloud-layer)
    - [9I — Database Failure (Cloud Layer)](#flow-9i--database-failure-cloud-layer)
    - [9J — Parameter Store Unavailability (Config Layer)](#flow-9j--parameter-store-unavailability-config-layer)
    - [9K — Bad Firmware Update (Config Layer)](#flow-9k--bad-firmware-update-config-layer)
    - [9L — Bad Infrastructure Deploy (Config Layer)](#flow-9l--bad-infrastructure-deploy---cicd-pipeline-config-layer)
    - [9M — Monitoring Stack Failure (Observability Layer)](#flow-9m--monitoring-stack-failure-observability-layer)
- [Flow 10 — Firmware Update](#flow-10--firmware-update)
- [Flow 11 — Scale Up / Scale Down](#flow-11--scale-up--scale-down)
- [Known Limitations](#known-limitations)
- [Future Enhancements (Post-MVP)](#future-enhancements-post-mvp)

---

## Flow 1 — Startup Sequence (Happy Path)

### Bluetooth Pairing

```
[Rider] → [Helmet]                        : power on signal                                                         : when rider switches helmet on

[Helmet] → [Smartphone]                   : bluetooth pairing request                                               : immediately after power on
[Smartphone] → [Helmet]                   : pairing confirmation                                                    : on successful bluetooth connection

[Helmet] → [Helmet HUD]                   : "Connection successful"                                                 : on pairing confirmation
[Smartphone App] → [Rider]                : "Connection successful"                                                 : on pairing confirmation
```

### Cloud Connectivity Check

```
[Smartphone] → [Telemetry Infrastructure] : connectivity check                                                      : after bluetooth pairing confirmed
[Telemetry Infrastructure] → [Smartphone] : connectivity confirmation                                               : on receiving connectivity check
[Smartphone App] → [Rider]                : "Cloud connection up"                                                   : on connectivity confirmation
[Smartphone] → [AWS IoT Core]             : MQTT session established, subscribe to helmet/{helmet_id}/infra/status  : on connectivity confirmation
```

### Sensor Health Check

```
[Helmet] → [Helmet]                       : sensor health check                                                     : after bluetooth pairing confirmed
```

---

### Branch A — Health Check Pass

```
[Helmet] → [Smartphone]                   : health check passed, helmet ID, timestamp                               : on clean health check
[Smartphone] → [Telemetry Infrastructure] : health check passed, helmet ID, timestamp                               : immediately
```

#### Buffer Check (runs only on Health Check Pass)

```
[Helmet] → [Helmet]                       : check buffer storage                                                    : after health check pass
```

##### Sub-branch A1 — Buffer Empty
> Proceed directly to Normal Telemetry below. No additional steps.

##### Sub-branch A2 — Buffer Non-Empty

```
[Helmet] → [Smartphone]                   : buffered telemetry data, helmet ID, timestamp                           : on non-empty buffer detected
[Smartphone] → [Telemetry Infrastructure] : buffered telemetry data, helmet ID, timestamp                           : immediately
[Telemetry Infrastructure] → [Hot Storage] : buffered telemetry data, helmet ID, timestamp range                   : on receiving buffered data
[Telemetry Infrastructure] → [Smartphone] : sync acknowledgement                                                    : on receiving buffered data
[Smartphone] → [Helmet]                   : sync acknowledgement                                                    : immediately
[Helmet] → [Helmet]                       : clear buffer storage                                                    : on receiving sync acknowledgement
[Telemetry Infrastructure] → [Telemetry Infrastructure] : inspect buffered data for crash flag                      : immediately
[Telemetry Infrastructure] → [SQS Crash Queue] : crash event data point, helmet ID, timestamp                         : if crash flag found
[Processing Infrastructure] → [SQS Crash Queue] : read crash event data point                                         : event-driven
[Processing Infrastructure] → [Hot Storage] : query telemetry history for helmet ID                                 : immediately on crash event received
[Processing Infrastructure] → [Processing Infrastructure] : scan for alert events in buffered data                  : immediately
```

> After buffer cleared — proceed to Normal Telemetry below.

---

### Normal Telemetry (after buffer cleared or buffer was empty)

```
[Helmet Sensors] → [Helmet]               : accelerometer, speed, edge result, helmet ID, timestamp                 : every 1 second
[Helmet] → [Smartphone]                   : telemetry payload, helmet ID, timestamp                                 : every 1 second
[Smartphone] → [Telemetry Infrastructure] : JSON array of 10 telemetry payloads + GPS + user ID + batch timestamp   : every 10 seconds
[Telemetry Infrastructure] → [Hot Storage]: batch payload, batch timestamp                                          : on every receive
```

---

### Branch B — Health Check Fail

```
[Helmet] → [Smartphone]                   : maintenance flag, fault details, helmet ID, timestamp                   : on failed health check
[Smartphone] → [Telemetry Infrastructure] : maintenance flag, fault details, helmet ID, timestamp                   : immediately
[Telemetry Infrastructure] → [Cold Storage] : maintenance needed, helmet ID, fault details                          : on receiving maintenance flag
[Helmet HUD] → [Rider]                    : "Alert mechanism offline — maintenance required"                        : on failed health check
[Helmet] → [Helmet]                       : stop all sensor transmission                                            : after maintenance flag sent
```

---

## Flow 2 — Startup Sequence Sad Paths

### Sad Path 1 — Bluetooth Pairing Fails

> **Precondition:** Helmet is on. Bluetooth pairing fails to establish.

#### Retry Loop

```
[Helmet] → [Helmet HUD]                   : "Connecting to smartphone, attempt 1 of 5"                             : on each retry
[Helmet] → [Helmet]                       : retry bluetooth pairing                                                 : up to 5 attempts per power-on
[Helmet] → [Helmet]                       : increment local retry counter                                           : on each failed attempt
```

#### After 5 Failed Attempts

```
[Helmet HUD] → [Rider]                    : "Unable to connect to smartphone — telemetry and alert system not operational" : after 5th failed attempt
[Helmet HUD] → [Rider]                    : "Please visit maintenance shop"                                         : after 5th failed attempt
[Helmet] → [Helmet]                       : retain buffer storage, do not clear                                     : at all times until sync confirmation received
```

#### On Future Successful Pairing

```
[Helmet] → [Smartphone]                   : buffered telemetry data + cumulative local retry count + helmet ID + timestamp : on successful pairing
[Smartphone] → [Telemetry Infrastructure] : buffered telemetry data + cumulative retry count + helmet ID + timestamp : immediately
[Telemetry Infrastructure] → [Cold Storage] : cumulative retry count update, helmet ID, timestamp                   : on receive
[Telemetry Infrastructure] → [Smartphone] : sync acknowledgement                                                    : on successful storage
[Smartphone] → [Helmet]                   : sync acknowledgement                                                    : immediately
[Helmet] → [Helmet]                       : clear buffer storage                                                    : on receiving sync acknowledgement
```

#### Local Counter Threshold Warning

```
[Helmet] → [Helmet HUD]                   : "Persistent connection issues — maintenance recommended"                : when local counter crosses 50 cumulative retries
```

#### Fleet Manager Counter Reset

```
[Fleet Manager] → [Fleet Management System]        : reset helmet counter request, helmet ID                        : when maintenance is completed
[Fleet Management System] → [Telemetry Infrastructure] : counter reset request, helmet ID, timestamp                : immediately
[Telemetry Infrastructure] → [Helmet]              : reset local retry counter command                              : via smartphone on next successful sync
[Helmet] → [Helmet]                                : reset local counter                                            : on receiving reset command
[Telemetry Infrastructure] → [Cold Storage]        : counter reset event logged, helmet ID, timestamp, reset authorised by Fleet Manager : immediately
```

---

### Sad Path 2A — Smartphone Has No Internet

> **Precondition:** Bluetooth pairing succeeded. Smartphone has no internet connection.

#### Initial Notification

```
[Smartphone] → [Helmet]                   : no internet connectivity detected                                       : on connectivity check
[Helmet HUD] → [Rider]                    : "No internet connectivity — telemetry and alert system not operational" : immediately
[Smartphone App] → [Rider]                : "No internet connectivity — alert system not operational"               : immediately
```

#### Helmet Continues Collecting — Smartphone Buffers Locally

```
[Helmet Sensors] → [Helmet]               : accelerometer, speed, edge result, helmet ID, timestamp                 : every 1 second
[Helmet] → [Smartphone]                   : telemetry payload, helmet ID, timestamp                                 : every 1 second
[Smartphone] → [Smartphone Local Storage] : telemetry payload                                                       : every 1 second, until internet restores
```

#### On Internet Restore

```
[Smartphone] → [Helmet HUD]               : "Internet connectivity restored"                                        : on connectivity restore
[Smartphone App] → [Rider]                : "Internet connectivity restored — telemetry and alert system operational" : immediately
```

#### Backlog Flush via Catch-Up Channel

```
[Smartphone] → [Telemetry Infrastructure — Catch-up Channel] : 50-second chunk of backlog data, chunk sequence number, helmet ID, timestamp range : starting from oldest unacknowledged chunk
[Telemetry Infrastructure] → [Smartphone] : chunk acknowledgement, chunk sequence number                            : on receiving full 50-second chunk
[Smartphone] → [Telemetry Infrastructure — Catch-up Channel] : next 50-second chunk                                 : on receiving acknowledgement of previous chunk
```

##### Partial Chunk or No Acknowledgement

```
[Smartphone] → [Telemetry Infrastructure — Catch-up Channel] : resend same chunk in full                            : if no acknowledgement received within timeout
```

##### Duplicate Chunk Detection

```
[Telemetry Infrastructure] → [Telemetry Infrastructure] : check timestamp range against existing Hot Storage entries : on every chunk receive
[Telemetry Infrastructure] → [Telemetry Infrastructure] : discard duplicate chunk                                   : if timestamp range already exists in Hot Storage
[Telemetry Infrastructure] → [Smartphone] : acknowledgement                                                         : on duplicate detected, so smartphone moves to next chunk
```

#### Live Data Resumes Alongside Catch-Up Channel

```
[Smartphone] → [Telemetry Infrastructure — Live Channel] : JSON array of 10 telemetry payloads + GPS + user ID + batch timestamp : every 10 seconds
[Telemetry Infrastructure] → [Hot Storage] : live batch payload                                                     : on every receive
[Telemetry Infrastructure] → [Hot Storage] : acknowledged chunk payload                                             : on each confirmed chunk
```

#### Backlog Fully Flushed

```
[Smartphone] → [Smartphone]               : all chunks acknowledged, backlog fully flushed                          : after final chunk acknowledgement received
[Smartphone] → [Smartphone Local Storage] : clear backlog data                                                      : immediately after full flush confirmed
```

---

### Sad Path 2B — Telemetry Infrastructure Unreachable

> **Precondition:** Bluetooth pairing succeeded. Smartphone has internet. Telemetry Infrastructure does not respond.

#### Initial Detection

```
[Smartphone] → [Telemetry Infrastructure] : connectivity check                                                      : after bluetooth pairing confirmed
[Telemetry Infrastructure] → [Smartphone] : no response                                                             : —

[Smartphone App] → [Rider]                : "Telemetry Infrastructure unreachable — not a device issue, please be patient" : immediately
[Helmet HUD] → [Rider]                    : "Telemetry Infrastructure unreachable — alert and telemetry systems not operational" : immediately
```

#### Infrastructure-Side Outage Detection

```
[Monitoring Infrastructure] → [Telemetry Infrastructure] : health check                                             : at regular intervals
[Telemetry Infrastructure] → [Monitoring Infrastructure] : no response                                              : —
[Monitoring Infrastructure] → [Infrastructure Engineer]  : outage alert, telemetry infrastructure unreachable, timestamp : after health check failure threshold crossed
```

#### Helmet and Smartphone Behaviour During Outage

> Same as Sad Path 2A — smartphone buffers locally until infrastructure restores.

```
[Helmet Sensors] → [Helmet]               : accelerometer, speed, edge result, helmet ID, timestamp                 : every 1 second
[Helmet] → [Smartphone]                   : telemetry payload, helmet ID, timestamp                                 : every 1 second
[Smartphone] → [Smartphone Local Storage] : telemetry payload                                                       : every 1 second until infra restores
```

#### On Infrastructure Restore

```
[Monitoring Infrastructure] → [Telemetry Infrastructure] : health check                                             : at regular intervals
[Telemetry Infrastructure] → [Monitoring Infrastructure] : health check passed                                      : on recovery
[Monitoring Infrastructure] → [Infrastructure Engineer]  : telemetry infrastructure restored, timestamp             : immediately
[Smartphone] → [Helmet HUD]               : "Telemetry Infrastructure restored"                                     : on successful connectivity check
[Smartphone App] → [Rider]                : "Telemetry Infrastructure restored — telemetry and alert systems operational" : immediately
```

#### Backlog Flush and Clear

> Identical to Sad Path 2A backlog flush. Full sequence repeated below for completeness.

```
[Smartphone] → [Telemetry Infrastructure — Catch-up Channel] : 50-second chunk of backlog data, chunk sequence number, helmet ID, timestamp range : starting from oldest unacknowledged chunk
[Telemetry Infrastructure] → [Smartphone] : chunk acknowledgement, chunk sequence number                            : on receiving full 50-second chunk
[Smartphone] → [Telemetry Infrastructure — Catch-up Channel] : next 50-second chunk                                 : on receiving acknowledgement of previous chunk
[Smartphone] → [Telemetry Infrastructure — Catch-up Channel] : resend same chunk in full                            : if no acknowledgement received within timeout
[Telemetry Infrastructure] → [Telemetry Infrastructure] : check timestamp range against existing Hot Storage entries : on every chunk receive
[Telemetry Infrastructure] → [Telemetry Infrastructure] : discard duplicate chunk                                   : if timestamp range already exists in Hot Storage
[Telemetry Infrastructure] → [Smartphone] : acknowledgement                                                         : on duplicate detected
[Smartphone] → [Telemetry Infrastructure — Live Channel] : JSON array of 10 telemetry payloads + GPS + user ID + batch timestamp : every 10 seconds
[Telemetry Infrastructure] → [Hot Storage] : live batch payload                                                     : on every receive
[Telemetry Infrastructure] → [Hot Storage] : acknowledged chunk payload                                             : on each confirmed chunk
[Smartphone] → [Smartphone]               : all chunks acknowledged, backlog fully flushed                          : after final chunk acknowledgement received
[Smartphone] → [Smartphone Local Storage] : clear backlog data                                                      : immediately after full flush confirmed
```

---

### Sad Path 2C — Buffer Sync Fails on Forward to Telemetry Infrastructure

> **Precondition:** Helmet has buffered data. Smartphone received it successfully via bluetooth. Smartphone has internet. Telemetry Infrastructure is up. Forward from smartphone to cloud fails.
>
> Helmet buffer is **not** cleared until the full ack chain completes.
> TTL for unconfirmed chunks = 24 hours (stored in Parameter Store).

#### Rider Status During Sync Attempt

```
[Smartphone App] → [Rider]                : "Data sync in progress"                                                 : on receiving buffered data from helmet
[Helmet HUD] → [Rider]                    : "Data sync in progress"                                                 : on receiving buffered data from helmet
[Smartphone App] → [Rider]                : "Alert and telemetry systems operational"                               : on connectivity confirmed
[Helmet HUD] → [Rider]                    : "Alert and telemetry systems operational"                               : on connectivity confirmed
```

#### Smartphone Forwards Buffer via Catch-Up Channel

```
[Smartphone] → [Telemetry Infrastructure — Catch-up Channel] : 50-second chunk of backlog data, chunk sequence number, helmet ID, timestamp range : starting from oldest chunk
```

---

#### Case 1 — DB Full

```
[Telemetry Infrastructure] → [Smartphone] : storage full error, chunk sequence number                               : on write rejection

[Smartphone App] → [Rider]                : "Buffer sync paused — cloud storage full, retrying when resolved"       : immediately
[Helmet HUD] → [Rider]                    : "Buffer sync paused — cloud storage issue, alert system still operational" : immediately

[Monitoring Infrastructure] → [Telemetry Infrastructure] : storage utilisation check                                : at regular intervals
[Monitoring Infrastructure] → [Infrastructure Engineer]  : storage full alert, helmet ID, timestamp                 : when threshold breached

[Smartphone] → [Smartphone Local Storage] : retain chunk, mark as undelivered                                       : immediately on storage full error

[Infrastructure Engineer] → [Telemetry Infrastructure]   : provision additional storage                             : on receiving alert
```

##### On Storage Restored — Resume Catch-Up Flow

```
[Smartphone] → [Telemetry Infrastructure — Catch-up Channel] : retry undelivered chunk, chunk sequence number, helmet ID, timestamp range : on storage restored
[Telemetry Infrastructure] → [Smartphone] : chunk acknowledgement, chunk sequence number                            : on successful write
[Smartphone] → [Helmet]                   : sync acknowledgement for cleared chunk                                  : immediately
[Helmet] → [Helmet]                       : clear that chunk from buffer storage                                    : on receiving acknowledgement
[Smartphone] → [Smartphone Local Storage] : clear that chunk                                                        : immediately after helmet confirms clear
[Telemetry Infrastructure] → [Hot Storage] : telemetry data from acknowledged chunk                                 : on each confirmed chunk write
```

---

#### Case 2 — Corrupt Data

```
[Telemetry Infrastructure] → [Smartphone] : bad payload error, chunk sequence number, timestamp range               : on validation failure

[Smartphone] → [Helmet]                   : resend chunk request, chunk sequence number, timestamp range            : immediately on bad payload error
[Helmet] → [Smartphone]                   : buffered chunk data, chunk sequence number, helmet ID, timestamp        : on resend request

[Smartphone] → [Telemetry Infrastructure — Catch-up Channel] : resent chunk data, chunk sequence number, helmet ID, timestamp range : immediately (attempt 2)
```

##### Sub-branch — Resend Accepted

```
[Telemetry Infrastructure] → [Smartphone] : chunk acknowledgement, chunk sequence number                            : on successful write
[Smartphone] → [Helmet]                   : sync acknowledgement for that chunk                                     : immediately
[Helmet] → [Helmet]                       : clear that chunk from buffer storage                                    : on receiving acknowledgement
[Smartphone] → [Smartphone Local Storage] : clear that chunk                                                        : immediately after helmet confirms clear
[Telemetry Infrastructure] → [Hot Storage] : telemetry data from acknowledged chunk                                 : on each confirmed chunk write
```

##### Sub-branch — Resend Rejected (Discard and Log)

```
[Telemetry Infrastructure] → [Smartphone] : bad payload error, chunk sequence number, timestamp range               : on second validation failure
[Telemetry Infrastructure] → [Cold Storage] : corrupt chunk log entry, helmet ID, chunk timestamp range, rejection reason, resend attempted true, resend outcome failed, logged at : immediately
[Smartphone] → [Helmet]                   : discard chunk command, chunk sequence number, timestamp range           : immediately
[Helmet] → [Helmet]                       : clear that chunk from buffer storage                                    : on receiving discard command
[Smartphone] → [Smartphone Local Storage] : clear that chunk                                                        : immediately after helmet confirms clear
```

##### Corrupt Rejection Monitoring

```
[Monitoring Infrastructure] → [Cold Storage]             : query corrupt rejection count for helmet ID              : at regular intervals
[Monitoring Infrastructure] → [Infrastructure Engineer]  : corrupt data threshold exceeded alert, helmet ID, timestamp : if count exceeds threshold in Parameter Store
```

---

#### Case 3 — Ack Lost (resolved by idempotency + TTL)

> **Context:** Infrastructure stored the chunk successfully, but the acknowledgement never reached the smartphone.

```
[Smartphone] → [Smartphone]               : ack timeout, no acknowledgement received                                : after 30 seconds
[Smartphone] → [Telemetry Infrastructure — Catch-up Channel] : resend same chunk, chunk sequence number, helmet ID, timestamp range : on timeout (attempt 2)

[Telemetry Infrastructure] → [Telemetry Infrastructure] : check timestamp range against existing Hot Storage entries : on every chunk receive
[Telemetry Infrastructure] → [Telemetry Infrastructure] : discard duplicate chunk                                   : timestamp range already exists in Hot Storage
[Telemetry Infrastructure] → [Smartphone] : chunk acknowledgement, chunk sequence number                            : on duplicate detected
```

##### If Ack Lost Again — Attempt 3

```
[Smartphone] → [Smartphone]               : ack timeout, no acknowledgement received                                : after 30 seconds
[Smartphone] → [Telemetry Infrastructure — Catch-up Channel] : resend same chunk, chunk sequence number, helmet ID, timestamp range : on timeout (attempt 3)
[Telemetry Infrastructure] → [Telemetry Infrastructure] : discard duplicate chunk                                   : timestamp range already exists in Hot Storage
[Telemetry Infrastructure] → [Smartphone] : chunk acknowledgement, chunk sequence number                            : on duplicate detected
```

##### If All 3 Attempts Fail

> Data is safe in infrastructure. Problem is ack not reaching smartphone.

```
[Smartphone] → [Smartphone]               : ack timeout after 3 attempts                                            : —
[Smartphone App] → [Rider]                : "Sync confirmation not received — possible connectivity issue on device" : immediately
[Helmet HUD] → [Rider]                    : "Sync confirmation not received — alert system status uncertain"        : immediately
[Smartphone] → [Smartphone Local Storage] : retain chunk, mark as unconfirmed, record chunk creation timestamp      : immediately
```

##### Duplicate Submission Monitoring

```
[Monitoring Infrastructure] → [Cold Storage]             : query duplicate submission count for helmet ID           : at regular intervals
[Monitoring Infrastructure] → [Infrastructure Engineer]  : repeated duplicate submissions detected, helmet ID, timestamp : if count exceeds threshold in Parameter Store
```

##### On Next Connectivity Restore

```
[Smartphone] → [Telemetry Infrastructure — Catch-up Channel] : resend chunk, chunk sequence number, helmet ID, timestamp range : on connectivity restore
[Telemetry Infrastructure] → [Telemetry Infrastructure] : discard duplicate chunk                                   : timestamp range already exists in Hot Storage
[Telemetry Infrastructure] → [Smartphone] : chunk acknowledgement, chunk sequence number                            : on duplicate detected
[Smartphone] → [Helmet]                   : sync acknowledgement for that chunk                                     : immediately
[Helmet] → [Helmet]                       : clear that chunk from buffer storage                                    : on receiving acknowledgement
[Smartphone] → [Smartphone Local Storage] : clear that chunk                                                        : immediately after helmet confirms clear
```

##### TTL Expiry — Chunk Held Unconfirmed Beyond 24 Hours

> TTL value stored in Parameter Store.

```
[Smartphone] → [Smartphone]               : check unconfirmed chunk age against TTL                                 : at regular intervals
[Smartphone] → [Smartphone]               : TTL expired for chunk                                                   : when chunk creation timestamp exceeds 24 hours
```

###### Forced Discard

```
[Smartphone] → [Helmet]                   : discard chunk command, chunk sequence number, timestamp range           : immediately on TTL expiry
[Helmet] → [Helmet]                       : clear that chunk from buffer storage                                    : on receiving discard command
[Smartphone] → [Smartphone Local Storage] : clear that chunk                                                        : immediately after helmet confirms clear
```

###### Log and Alert

```
[Telemetry Infrastructure] → [Cold Storage] : TTL expiry log entry, helmet ID, chunk timestamp range, chunk creation timestamp, discarded at, reason — ack never confirmed : immediately
[Monitoring Infrastructure] → [Infrastructure Engineer] : TTL expiry alert, helmet ID, chunk timestamp range, timestamp : immediately on log entry written
```

---

## Flow 3 — Crash Detection and Alert Flow

> **Precondition:** Rider is mid-ride. Helmet is active, sensors running normally. Smartphone has internet. Telemetry Infrastructure is reachable.
>
> This is the baseline crash detection and alert flow. All other flows that involve crash detection (Flow 4, Flow 6, Flow 7, Flow 8) reference this flow for core alert mechanics.

### Crash Detected by Edge Processing

```
[Helmet Sensors] → [Helmet]               : accelerometer spike, speed data, edge result flagged as crash, helmet ID, timestamp : on crash detection
[Helmet] → [Smartphone]                   : telemetry payload with crash flag, helmet ID, timestamp                 : immediately
[Smartphone] → [AWS IoT Core]             : telemetry payload with crash flag, helmet ID, timestamp                 : immediately via helmet/{helmet_id}/telemetry topic
[AWS IoT Core] → [Telemetry Infrastructure] : telemetry payload with crash flag, helmet ID, timestamp              : immediately via IoT Core rules engine
[Telemetry Infrastructure] → [Hot Storage] : telemetry payload with crash flag, helmet ID, timestamp               : immediately
[Telemetry Infrastructure] → [Telemetry Infrastructure] : inspect batch for crash flag                              : immediately
[Telemetry Infrastructure] → [SQS Crash Queue] : crash event data point, helmet ID, timestamp                         : on crash flag detected
[Processing Infrastructure] → [SQS Crash Queue] : read crash event data point                                         : event-driven
```

### Processing Infrastructure Validates Crash Event

```
[Processing Infrastructure] → [Hot Storage] : query recent telemetry history for helmet ID                         : immediately on reading crash event data point from SQS
[Hot Storage] → [Processing Infrastructure] : recent telemetry history                                              : immediately
[Processing Infrastructure] → [Processing Infrastructure] : validate crash event against telemetry history          : immediately
```

---

### Branch A — Validated as False Positive

```
[Processing Infrastructure] → [Processing Infrastructure] : false positive confirmed, no alert to fire              : on validation result
[Processing Infrastructure] → [SQS Alert Queue]           : false positive confirmed, alert type — false_positive, helmet ID, crash timestamp : immediately
```

> Processing Infrastructure does not interact with the rider. Alerting Infrastructure handles the override window. See Flow 3 — Alerting Infrastructure Alert Type Determination.

---

### Branch B — Validated as Genuine Crash

> Proceed directly to Alert Countdown below.

---

### Alerting Infrastructure Alert Type Determination

> This block runs every time Alerting Infrastructure reads an event from SQS Alert Queue, across all flows.

```
[Alerting Infrastructure] → [SQS Alert Queue]     : read alert event data point                                        : event-driven
[Alerting Infrastructure] → [Alerting Infrastructure] : check alert type label on event — false_positive, standard, or retrospective : immediately on read
```

#### Label — False Positive

```
[Alerting Infrastructure] → [AWS IoT Core]        : publish 5-second override window, helmet ID, timestamp          : immediately
[AWS IoT Core] → [Smartphone]                     : override message via MQTT topic                                 : immediately
[Smartphone App] → [Rider]                        : 5-second override window — "False positive detected"              : immediately
[Smartphone] → [Helmet HUD]                       : forward override message via Bluetooth                          : immediately
[Helmet HUD] → [Rider]                            : 5-second override window — "False positive detected"              : immediately
```

##### Sub-branch — Rider Does Nothing (Override Window Expires)

```
[Smartphone App] → [Rider]                        : dismiss notification                                            : on 5-second window expiry
[Helmet HUD] → [Rider]                            : dismiss notification                                            : on 5-second window expiry
[Alerting Infrastructure] → [Cold Storage]        : false positive log entry, helmet ID, crash timestamp, reason, no override : on 5-second window expiry
```

> No alert sent.

##### Sub-branch — Rider Overrides (Requests Fresh Countdown)

```
[Rider] → [Smartphone App]                        : override tap                                                    : within 5-second window
[Smartphone] → [AWS IoT Core]                     : publish override signal via MQTT                                : immediately
[AWS IoT Core] → [Alerting Infrastructure]        : route override signal                                           : immediately
[Alerting Infrastructure] → [Alerting Infrastructure] : override received, start fresh 30-second countdown        : immediately
```

> Proceed to Alert Countdown below.

#### Label — Retrospective

```
[Alerting Infrastructure] → [Alerting Infrastructure] : alert type is retrospective — proceed to retrospective notification : immediately
```

> Proceed to Retrospective Alert. See Flow 4 — Retrospective Alert.

#### Label — Standard

```
[Alerting Infrastructure] → [Alerting Infrastructure] : alert type is standard — check elapsed time since crash timestamp against standard alert threshold from Parameter Store : immediately
```

##### Within Threshold — Run Countdown

```
[Alerting Infrastructure] → [AWS IoT Core]        : publish 30-second countdown, helmet ID, timestamp               : immediately
[AWS IoT Core] → [Smartphone]                     : countdown message via MQTT topic                                : immediately
[Smartphone App] → [Rider]                        : 30-second countdown — "Crash detected — cancel to abort alert"    : immediately
[Smartphone] → [Helmet HUD]                       : forward countdown via Bluetooth                                 : immediately
[Helmet HUD] → [Rider]                            : 30-second countdown — "Crash detected — cancel to abort alert"    : immediately
```

> Cloud owns the countdown. Countdown displayed on both devices simultaneously.
> Rider cancels from either device — only one cancel needed. Proceed to Alert Countdown cancel and fire branches. See Flow 3 — Alert Countdown.

##### Beyond Threshold — Downgrade to Retrospective

```
[Alerting Infrastructure] → [Alerting Infrastructure] : elapsed time exceeds standard alert threshold — downgrade to retrospective, crash timestamp, helmet ID : immediately
```

> Proceed to Retrospective Alert. See Flow 4 — Retrospective Alert.

---

### Alert Countdown

```
[Processing Infrastructure] → [SQS Alert Queue]   : crash confirmed, alert type — standard, helmet ID, crash timestamp, incident location : on crash confirmation or rider override
```

> Alerting Infrastructure reads from SQS Alert Queue and applies alert type determination. See Flow 3 — Alerting Infrastructure Alert Type Determination.


#### Sub-branch — Rider Cancels Within Countdown

```
[Rider] → [Smartphone App]                        : cancel                                                          : within 30-second window
[Smartphone] → [AWS IoT Core]                     : publish cancel signal via MQTT                                  : immediately
[AWS IoT Core] → [Alerting Infrastructure]        : route cancel signal                                             : immediately
[Alerting Infrastructure] → [Alerting Infrastructure] : stop countdown                                              : immediately
[Alerting Infrastructure] → [AWS IoT Core]        : publish dismiss countdown, helmet ID, timestamp                 : immediately
[AWS IoT Core] → [Smartphone]                     : dismiss countdown message via MQTT topic                        : immediately
[Smartphone App] → [Rider]                        : dismiss countdown                                               : immediately
[Smartphone] → [Helmet HUD]                       : forward dismiss countdown via Bluetooth                         : immediately
[Helmet HUD] → [Rider]                            : dismiss countdown                                               : immediately
[Alerting Infrastructure] → [Cold Storage]        : cancelled alert record, helmet ID, crash timestamp, cancelled by rider : immediately
```

> No alert sent to Next of Kin or Emergency Services.

#### Sub-branch — Rider Does Not Cancel — Alert Fires on Countdown Expiry

```
[Alerting Infrastructure] → [Next of Kin]        : crash alert, incident location, current location, incident timestamp : on countdown expiry
[Alerting Infrastructure] → [Emergency Services] : crash alert, incident location, current location, incident timestamp, next of kin contact : on countdown expiry, independent of Next of Kin channel
```

> Retries on each channel do not block the other.

##### Delivery Success

```
[Next of Kin] → [Alerting Infrastructure]        : acknowledgement                                                  : on receiving alert
[Emergency Services] → [Alerting Infrastructure] : acknowledgement                                                  : on receiving alert
[Alerting Infrastructure] → [Cold Storage]       : delivery success log, helmet ID, channel, timestamp              : on each acknowledgement
```

##### Delivery Failure

```
[Alerting Infrastructure] → [Alerting Infrastructure] : retry alert, channel                                        : on no acknowledgement received
[Alerting Infrastructure] → [Cold Storage]       : delivery failure log, helmet ID, channel, attempt number, timestamp : on each failed attempt
```

##### Storage — Written Regardless of Outcome

```
[Alerting Infrastructure] → [Cold Storage]       : incident record, helmet ID, crash timestamp, incident location, current location at alert time, cancellation or delivery outcome per channel : immediately on resolution
```

---

## Flow 4 — Phone Dead During Crash

> **Precondition:** Rider is mid-ride. Smartphone is completely off — not low battery, fully dead. Helmet is active, sensors running normally. No bluetooth connection between helmet and smartphone.
>
> **Note:** Flow 5 (Retrospective Alert After Phone Revival) is absorbed into this flow. The retrospective alert logic is identical regardless of the reason for the delay — phone dead, no internet, or infrastructure unreachable. What matters is that the crash event reaches cloud after a delay and the same validation and alert mechanics apply.

### Crash Detected — No Cloud Path Available

```
[Helmet Sensors] → [Helmet]               : accelerometer spike, speed data, edge result flagged as crash, helmet ID, timestamp : on crash detection
[Helmet] → [Helmet]                       : check for smartphone connection                                         : immediately on crash detection
[Helmet] → [Helmet]                       : no smartphone connection detected                                       : immediately
[Helmet] → [Helmet]                       : store crash event + surrounding telemetry in buffer                     : immediately
[Helmet HUD] → [Rider]                    : "Alert system unavailable — event data stored"                          : immediately
```

> No 30-second countdown. No alert window. No action required from rider.

### Helmet Continues Operating — Buffer Only

```
[Helmet Sensors] → [Helmet]               : accelerometer, speed, edge result, helmet ID, timestamp                 : every 1 second
[Helmet] → [Helmet]                       : store all telemetry in buffer                                           : every 1 second
```

### Phone Revives — Normal Startup Sequence Runs

```
[Smartphone] → [Helmet]                   : bluetooth pairing request                                               : on smartphone power on
[Helmet] → [Smartphone]                   : pairing confirmation                                                    : on successful bluetooth connection
[Smartphone] → [Telemetry Infrastructure] : connectivity check                                                      : after bluetooth pairing confirmed
[Telemetry Infrastructure] → [Smartphone] : connectivity confirmation                                               : on receiving connectivity check
```

### Catch-Up Sync Initiates Automatically

> No special trigger. Buffer contains pre-crash telemetry + crash event + post-crash telemetry. All treated as regular buffered data — crash flag is just another datapoint.

```
[Helmet] → [Smartphone]                   : buffered telemetry data including crash event, helmet ID, timestamp range : on successful pairing
[Smartphone] → [Telemetry Infrastructure — Catch-up Channel] : 50-second chunk of backlog data, chunk sequence number, helmet ID, timestamp range : starting from oldest unacknowledged chunk
[Telemetry Infrastructure] → [Smartphone] : chunk acknowledgement, chunk sequence number                            : on receiving full 50-second chunk
[Smartphone] → [Telemetry Infrastructure — Catch-up Channel] : next 50-second chunk                                 : on receiving acknowledgement of previous chunk
[Telemetry Infrastructure] → [Hot Storage] : synced buffered data, helmet ID, timestamp range                       : on each acknowledged chunk
[Telemetry Infrastructure] → [Telemetry Infrastructure] : inspect synced chunk for crash flag                       : immediately
[Telemetry Infrastructure] → [SQS Crash Queue] : crash event data point, helmet ID, timestamp                         : if crash flag found in chunk
[Processing Infrastructure] → [SQS Crash Queue] : read crash event data point                                         : event-driven
[Processing Infrastructure] → [Processing Infrastructure] : scan for crash flag in synced data                      : immediately on reading data point from SQS
```

---

### Case A — Sync Within 24 Hours (Hot Storage Data Available)

```
[Processing Infrastructure] → [Hot Storage] : query recent telemetry for helmet ID                                  : immediately on reading data point from SQS
[Hot Storage] → [Processing Infrastructure] : recent telemetry history                                              : immediately
[Processing Infrastructure] → [Processing Infrastructure] : validate crash event against telemetry history          : immediately
```

##### Sub-branch — Validated as False Positive

```
[Processing Infrastructure] → [SQS Alert Queue] : false positive confirmed, alert type — false_positive, helmet ID, crash timestamp : on false positive decision
```

> Alerting Infrastructure reads the queue, checks the elapsed time against the threshold, and handles the logging/alerting. See Flow 3 — Alerting Infrastructure Alert Type Determination.

##### Sub-branch — Validated as Genuine Crash

> Proceed to Retrospective Alert below.

---

### Case B — Sync After 24 Hours (No Hot Storage Data Available)

```
[Processing Infrastructure] → [Hot Storage] : query recent telemetry for helmet ID                                  : immediately on reading data point from SQS
[Hot Storage] → [Processing Infrastructure] : no data found                                                         : immediately
[Processing Infrastructure] → [Processing Infrastructure] : validate crash event against buffered data only, apply lower confidence threshold, lean toward alert : immediately
```

> Proceed to Retrospective Alert below.

---

### Retrospective Alert (runs after Case A validated or Case B confirmed)

```
[Processing Infrastructure] → [SQS Alert Queue]         : crash confirmed, alert type — retrospective, helmet ID, crash timestamp, incident location from buffer, current location from phone : on crash confirmation
```

> Alerting Infrastructure reads from SQS Alert Queue. Label is retrospective — persistent notification shown immediately. See Flow 3 — Alerting Infrastructure Alert Type Determination.

```
[Alerting Infrastructure] → [AWS IoT Core]        : publish persistent notification, helmet ID, timestamp           : immediately
[AWS IoT Core] → [Smartphone]                     : persistent notification message via MQTT topic                  : immediately
[Smartphone App] → [Rider]                        : persistent notification — "Crash detected at [timestamp] — Alert emergency services?"                  : immediately
[Smartphone] → [Helmet HUD]                       : forward persistent notification via Bluetooth                   : immediately
[Helmet HUD] → [Rider]                            : persistent notification — "Crash detected at [timestamp] — Alert emergency services?"                  : immediately
```

> No countdown. Notification persists until rider explicitly acts from either device.

#### Sub-branch — Rider Cancels

```
[Rider] → [Smartphone App or Helmet HUD]          : cancel                                                          : on rider action
[Smartphone] → [AWS IoT Core]                     : publish cancel signal via MQTT                                  : immediately
[AWS IoT Core] → [Alerting Infrastructure]        : route cancel signal                                             : immediately
[Alerting Infrastructure] → [AWS IoT Core]        : publish dismiss notification, helmet ID, timestamp              : immediately
[AWS IoT Core] → [Smartphone]                     : dismiss notification message via MQTT topic                     : immediately
[Smartphone App] → [Rider]                        : dismiss notification                                            : immediately
[Smartphone] → [Helmet HUD]                       : forward dismiss notification via Bluetooth                      : immediately
[Helmet HUD] → [Rider]                            : dismiss notification                                            : immediately
[Alerting Infrastructure] → [Cold Storage]        : incident log entry, helmet ID, crash timestamp, incident location, cancelled at, cancelled by rider : immediately
```

> No alert sent to Next of Kin or Emergency Services.

#### Sub-branch — Rider Confirms or Does Not Respond

```
[Alerting Infrastructure] → [Next of Kin]         : crash alert, incident location, current location, incident timestamp                                   : immediately on confirm or no response
[Alerting Infrastructure] → [Emergency Services]  : crash alert, incident location, current location, incident timestamp, speed at time of crash, next of kin contact : immediately, independent of Next of Kin channel
```

> Retries on each channel do not block the other.

##### Delivery Success

```
[Next of Kin] → [Alerting Infrastructure]         : acknowledgement                                                 : on receiving alert
[Emergency Services] → [Alerting Infrastructure]  : acknowledgement                                                 : on receiving alert
[Alerting Infrastructure] → [Cold Storage]        : delivery success log, helmet ID, channel, timestamp             : on each acknowledgement
```

##### Delivery Failure

```
[Alerting Infrastructure] → [Alerting Infrastructure] : retry alert, channel                                        : on no acknowledgement received
[Alerting Infrastructure] → [Cold Storage]        : delivery failure log, helmet ID, channel, attempt number, timestamp : on each failed attempt
```

##### Storage — Written Regardless of Outcome

```
[Alerting Infrastructure] → [Cold Storage]        : incident record, helmet ID, crash timestamp, incident location, current location at alert time, confirmation or cancellation, delivery outcome per channel : immediately on resolution
```

---

## Flow 5 — Retrospective Alert After Phone Revival

> **Absorbed into Flow 4.** See Flow 4 — Retrospective Alert section.
>
> The retrospective alert logic is identical regardless of why the crash event was delayed reaching the cloud. The trigger, validation cases, notification, and delivery chain are the same whether the delay was caused by phone death, no internet, or infrastructure unreachable.

---

## Flow 6 — Graceful Shutdown

### Happy Path — Clean Shutdown

> **Precondition:** Rider switches helmet off. Smartphone has internet. Telemetry Infrastructure is reachable.

```
[Rider] → [Helmet]                        : power off signal                                                        : when rider switches helmet off

[Helmet] → [Smartphone]                   : remaining unsent telemetry payloads, helmet ID, timestamp               : immediately on power off signal
[Smartphone] → [Telemetry Infrastructure — Live Channel] : remaining telemetry payloads, helmet ID, timestamp       : immediately
[Telemetry Infrastructure] → [Hot Storage] : remaining telemetry payloads                                           : on receive
[Telemetry Infrastructure] → [Smartphone] : telemetry acknowledgement                                               : on successful write

[Helmet] → [Smartphone]                   : graceful shutdown message, helmet ID, timestamp                         : after remaining telemetry flushed
[Smartphone] → [Telemetry Infrastructure] : graceful shutdown message, helmet ID, timestamp                         : immediately
[Telemetry Infrastructure] → [Hot Storage] : graceful shutdown message, helmet ID, timestamp                        : immediately
[Telemetry Infrastructure] → [SQS Control Queue] : graceful shutdown message data point, helmet ID, timestamp          : immediately
[Processing Infrastructure] → [SQS Control Queue] : read graceful shutdown message data point                          : event-driven
[Processing Infrastructure] → [Processing Infrastructure] : mark helmet as gracefully offline                       : immediately
[Processing Infrastructure] → [Telemetry Infrastructure] : shutdown acknowledgement, helmet ID, timestamp           : immediately
[Telemetry Infrastructure] → [Smartphone] : shutdown acknowledgement, helmet ID, timestamp                          : immediately
[Smartphone] → [Helmet]                   : shutdown acknowledgement                                                : immediately
[Helmet] → [Helmet]                       : power down                                                              : on receiving shutdown acknowledgement

[Smartphone App] → [Rider]                : "Riding session ended — helmet is now offline"                          : on shutdown acknowledgement received

[Processing Infrastructure] → [Hot Storage] : start 24-hour retention window, helmet ID, last telemetry batch timestamp : immediately on graceful shutdown marked
```

> No cold storage write. No alert triggered. Graceful shutdown is a normal event.

---

### Sad Path — Shutdown Acknowledgement Not Received

> **Precondition:** Rider switches helmet off. Acknowledgement not received within 10 seconds. Helmet powers down regardless — buffer retained.

```
[Rider] → [Helmet]                        : power off signal                                                        : when rider switches helmet off
[Helmet] → [Smartphone]                   : remaining unsent telemetry payloads, helmet ID, timestamp               : immediately on power off signal
[Helmet] → [Smartphone]                   : graceful shutdown message, helmet ID, timestamp                         : after remaining telemetry flushed
[Helmet] → [Helmet]                       : start 10-second acknowledgement timer                                   : immediately after shutdown message sent
[Helmet] → [Helmet]                       : no acknowledgement received within 10 seconds                           : on timer expiry
[Helmet] → [Helmet]                       : power down, retain buffer storage                                       : on timer expiry
```

> Helmet powers down without cloud acknowledgement. Buffer retained — data not lost.
>
> From cloud perspective — no shutdown message received. LWT fires automatically. Cloud treats as Flow 8 (Unexpected Dropout / Type 3). Flow 8 runs independently and is not modified here.

```
[Smartphone] → [Smartphone Local Storage] : buffered telemetry payloads, graceful shutdown message, helmet ID, timestamp : immediately on helmet power down
```

#### On Connectivity Restore — Smartphone Syncs Buffer

```
[Smartphone] → [Telemetry Infrastructure — Catch-up Channel] : buffered telemetry payloads, graceful shutdown message, helmet ID, timestamp range : on connectivity restore
[Telemetry Infrastructure] → [Hot Storage]                   : buffered telemetry payloads, helmet ID, timestamp range : immediately
[Telemetry Infrastructure] → [SQS Control Queue]             : graceful shutdown message data point, helmet ID, timestamp : immediately
[Processing Infrastructure] → [SQS Control Queue]            : read graceful shutdown message data point                  : event-driven
[Processing Infrastructure] → [Hot Storage]                  : query telemetry history for helmet ID                   : immediately on reading data point from SQS
[Telemetry Infrastructure] → [Smartphone]                    : acknowledgement                                          : on successful receive
```

#### Processing Infrastructure Checks Flow 8 Status

```
[Processing Infrastructure] → [Processing Infrastructure] : check Flow 8 process status for helmet ID              : on receiving graceful shutdown message
```

---

#### Scenario 1 — Flow 8 Identified False Positive, No Alert Fired

```
[Processing Infrastructure] → [Processing Infrastructure] : graceful shutdown confirmed, false positive validated, no alert was fired : on status check
[Telemetry Infrastructure] → [Hot Storage] : buffered telemetry payloads                                            : on receive
[Smartphone App] → [Rider]                : "Riding session ended — helmet is now offline"                          : on graceful shutdown confirmed
```

> Hot storage retention window — 24 hours from last telemetry batch timestamp.
> False alert event log already written to cold storage during Flow 8 process — nothing new added.

---

#### Scenario 2A — Alert Countdown Still Active When Buffered Data Arrives

```
[Processing Infrastructure] → [Processing Infrastructure] : graceful shutdown message received, alert countdown still active : on status check
[Processing Infrastructure] → [Alerting Infrastructure]  : cancel alert countdown, helmet ID, timestamp, reason — graceful shutdown confirmed : immediately
[Alerting Infrastructure] → [Alerting Infrastructure]    : cancel alert countdown                                   : immediately
[Alerting Infrastructure] → [Smartphone App]             : "Alert cancelled — graceful shutdown confirmed"          : immediately
[Smartphone App] → [Rider]                               : "Alert was triggered but has been cancelled — your session ended safely" : immediately
```

> Helmet is powered down — no HUD notification possible.

```
[Smartphone App] → [Rider]                : "Do you want to alert emergency services anyway?"                       : immediately
```

##### Sub-branch — Rider Confirms Manual Alert

```
[Rider] → [Smartphone App]                : confirm                                                                 : on rider action
[Smartphone App] → [Alerting Infrastructure] : manual alert request, helmet ID, timestamp, initiated by rider via smartphone : immediately
[Alerting Infrastructure] → [Next of Kin]         : crash alert, incident location, current location, incident timestamp : immediately
[Alerting Infrastructure] → [Emergency Services]  : crash alert, incident location, current location, incident timestamp, next of kin contact : immediately, independent of Next of Kin channel
[Alerting Infrastructure] → [Cold Storage]        : manual alert record, helmet ID, timestamp, initiated by rider, channel delivery outcomes : on resolution
```

##### Sub-branch — Rider Cancels

```
[Rider] → [Smartphone App]                : cancel                                                                  : on rider action
[Alerting Infrastructure] → [Cold Storage] : alert cancelled record, helmet ID, timestamp, cancelled by rider after graceful shutdown confirmed : immediately
```

```
[Telemetry Infrastructure] → [Hot Storage] : buffered telemetry payloads                                            : on receive (regardless of rider choice)
```

---

#### Scenario 2B — Alert Already Fired Before Buffered Data Arrives

```
[Processing Infrastructure] → [Processing Infrastructure] : graceful shutdown message received, alert already fired : on status check
[Alerting Infrastructure] → [Smartphone App] : "Alert has already been sent to Next of Kin and Emergency Services"  : immediately
[Smartphone App] → [Rider]                : "Next of Kin and Emergency Services have been alerted — do you want to notify them the rider is safe?" : immediately
```

##### Sub-branch — Rider Confirms (Notify That Rider Is Safe)

```
[Rider] → [Smartphone App]                : confirm                                                                 : on rider action
[Smartphone App] → [Alerting Infrastructure] : rider safe notification request, helmet ID, timestamp, initiated by rider : immediately
[Alerting Infrastructure] → [Next of Kin]         : rider safe notification — previous alert was a false positive   : immediately
[Alerting Infrastructure] → [Emergency Services]  : rider safe notification — previous alert was a false positive   : immediately, independent of Next of Kin channel
[Alerting Infrastructure] → [Cold Storage]        : rider safe notification record, helmet ID, timestamp, rider choice confirmed, channel delivery outcomes : immediately
```

##### Sub-branch — Rider Declines

```
[Rider] → [Smartphone App]                : cancel                                                                  : on rider action
[Alerting Infrastructure] → [Cold Storage] : rider safe notification declined, helmet ID, timestamp, rider choice declined : immediately
```

```
[Telemetry Infrastructure] → [Hot Storage] : buffered telemetry payloads                                            : on receive (regardless of rider choice)
```

---

## Flow 7 — Battery Death

> **Precondition:** Rider is mid-ride. Helmet battery dropping.
>
> Battery thresholds are read from Parameter Store at session startup. Helmet reads thresholds via smartphone relay and stores locally for session duration.
> - 10% threshold → low battery warning
> - 5% threshold → shutdown message
>
> Rationale: 5% battery = at least 1 minute of operation on any commercially viable device. Full alert mechanics can run within this window.

### 10% Low Battery Warning

```
[Helmet] → [Helmet]                       : battery level check against threshold                                   : continuously
[Helmet] → [Helmet]                       : battery at 10% threshold detected                                       : on threshold breach
[Helmet] → [Smartphone]                   : low battery warning, battery percentage, helmet ID, timestamp           : immediately
[Smartphone] → [Telemetry Infrastructure] : low battery warning, battery percentage, helmet ID, timestamp           : immediately
[Telemetry Infrastructure] → [Hot Storage] : low battery warning, battery percentage, helmet ID, timestamp          : immediately
[Telemetry Infrastructure] → [SQS Control Queue] : low battery warning data point, helmet ID, timestamp               : immediately
[Processing Infrastructure] → [SQS Control Queue] : read low battery warning data point                               : event-driven
[Processing Infrastructure] → [Processing Infrastructure] : mark helmet as low battery, helmet ID, timestamp        : immediately
[Helmet HUD] → [Rider]                    : "Low battery — system shutdown at 5%"                                   : immediately
[Smartphone App] → [Rider]                : "Helmet battery low — system shutdown at 5%"                            : immediately
```

> Normal operations continue — no change to telemetry frequency or alert mechanics.

```
[Helmet Sensors] → [Helmet]               : accelerometer, speed, edge result, helmet ID, timestamp                 : every 1 second
[Helmet] → [Smartphone]                   : telemetry payload, helmet ID, timestamp                                 : every 1 second
[Smartphone] → [Telemetry Infrastructure — Live Channel] : JSON array of 10 telemetry payloads + GPS + user ID + batch timestamp : every 10 seconds
[Telemetry Infrastructure] → [Hot Storage] : batch payload, batch timestamp                                         : on every receive
```

### 5% Shutdown Message

```
[Helmet] → [Helmet]                       : battery at 5% threshold detected                                        : on threshold breach
[Helmet] → [Smartphone]                   : shutdown message, last telemetry payload, battery percentage, helmet ID, timestamp : immediately
[Smartphone] → [Telemetry Infrastructure] : shutdown message, last telemetry payload, battery percentage, helmet ID, timestamp : immediately
[Telemetry Infrastructure] → [Hot Storage] : shutdown message, last telemetry payload, battery percentage, helmet ID, timestamp : immediately
[Telemetry Infrastructure] → [SQS Control Queue] : shutdown message data point, helmet ID, timestamp                   : immediately
[Processing Infrastructure] → [SQS Control Queue] : read shutdown message data point                                   : event-driven
[Processing Infrastructure] → [Hot Storage] : query last telemetry for helmet ID                                    : immediately on reading data point from SQS
[Helmet] → [Helmet]                       : start 15-second acknowledgement timer                                   : immediately after shutdown message sent
```

#### Processing Infrastructure Checks Last Telemetry for Crash Flag

```
[Processing Infrastructure] → [Processing Infrastructure] : check last telemetry for crash flag, helmet ID          : immediately on shutdown message received
```

---

### Case 1 — No Crash Flag in Last Telemetry

```
[Processing Infrastructure] → [Processing Infrastructure] : no crash flag detected, mark helmet as battery death offline, helmet ID, timestamp : immediately
[Processing Infrastructure] → [Telemetry Infrastructure] : shutdown acknowledgement, helmet ID, timestamp           : immediately
[Telemetry Infrastructure] → [Smartphone] : shutdown acknowledgement, helmet ID, timestamp                          : immediately
[Smartphone] → [Helmet]                   : shutdown acknowledgement                                                : immediately
[Helmet] → [Helmet]                       : power down on receiving acknowledgement                                 : immediately
[Smartphone App] → [Rider]                : "Riding session ended — helmet battery depleted"                        : on shutdown acknowledgement
[Processing Infrastructure] → [Hot Storage] : start 24-hour retention window, helmet ID, last telemetry batch timestamp : immediately
```

> No alert triggered. No cold storage write — battery death with no incident is a normal event.

---

### Case 2 — Crash Flag Present in Last Telemetry

```
[Processing Infrastructure] → [Processing Infrastructure] : crash flag detected in last telemetry, run validation   : immediately
[Processing Infrastructure] → [Hot Storage] : query recent telemetry history for helmet ID                         : immediately
[Hot Storage] → [Processing Infrastructure] : recent telemetry history                                              : immediately
```

#### Sub-branch — Validated as False Positive

```
[Processing Infrastructure] → [Processing Infrastructure] : false positive confirmed, no alert to fire              : on validation result
[Processing Infrastructure] → [SQS Alert Queue]           : false positive confirmed, alert type — false_positive, helmet ID, crash timestamp, reason, battery death context : immediately
[Processing Infrastructure] → [Telemetry Infrastructure] : shutdown acknowledgement, helmet ID, timestamp           : immediately
[Telemetry Infrastructure] → [Smartphone] : shutdown acknowledgement                                                : immediately
[Smartphone] → [Helmet]                   : shutdown acknowledgement                                                : immediately
[Helmet] → [Helmet]                       : power down on receiving acknowledgement                                 : immediately
[Smartphone App] → [Rider]                : "Riding session ended — helmet battery depleted"                        : on shutdown acknowledgement
```

#### Sub-branch — Validated as Genuine Crash

```
[Processing Infrastructure] → [Processing Infrastructure] : crash confirmed, proceed to alert                       : on validation result
[Processing Infrastructure] → [SQS Alert Queue]          : crash confirmed, alert type — standard, helmet ID, crash timestamp, incident location : immediately
```

> Alerting Infrastructure reads from SQS Alert Queue and applies alert type determination. See Flow 3 — Alerting Infrastructure Alert Type Determination.


> Helmet may power down during countdown — smartphone carries countdown alone if helmet dies.
> Cloud owns the countdown regardless of helmet status.

##### Rider Cancels from Smartphone

```
[Rider] → [Smartphone App]                        : cancel                                                          : within 30-second window
[Smartphone] → [AWS IoT Core]                     : publish cancel signal via MQTT                                  : immediately
[AWS IoT Core] → [Alerting Infrastructure]        : route cancel signal                                             : immediately
[Alerting Infrastructure] → [AWS IoT Core]        : publish dismiss countdown, helmet ID, timestamp                 : immediately
[AWS IoT Core] → [Smartphone]                     : dismiss countdown message via MQTT topic                        : immediately
[Smartphone App] → [Rider]                        : dismiss countdown                                               : immediately
[Smartphone] → [Helmet HUD]                       : forward dismiss countdown via Bluetooth                         : immediately
[Helmet HUD] → [Rider]                            : dismiss countdown if still active                               : immediately
[Alerting Infrastructure] → [Cold Storage]        : cancelled alert record, helmet ID, crash timestamp, cancelled by rider, battery death context : immediately
```

> No alert sent to Next of Kin or Emergency Services.

##### Rider Does Not Cancel — Alert Fires

```
[Alerting Infrastructure] → [Next of Kin]         : crash alert, incident location, current location, incident timestamp : on countdown expiry
[Alerting Infrastructure] → [Emergency Services]  : crash alert, incident location, current location, incident timestamp, next of kin contact : on countdown expiry, independent of Next of Kin channel
[Alerting Infrastructure] → [Cold Storage]        : incident record, helmet ID, crash timestamp, incident location, delivery outcome per channel : on resolution
```

##### Shutdown Acknowledgement — Sent After Alert Mechanics Initiated, Not Blocked by Alert Outcome

```
[Processing Infrastructure] → [Telemetry Infrastructure] : shutdown acknowledgement, helmet ID, timestamp           : immediately after alert mechanics initiated
[Telemetry Infrastructure] → [Smartphone] : shutdown acknowledgement                                                : immediately
[Smartphone] → [Helmet]                   : shutdown acknowledgement                                                : immediately
[Helmet] → [Helmet]                       : power down on receiving acknowledgement or on 15-second timer expiry    : whichever comes first
```

---

### Sad Path — 15-Second Timer Expires, No Acknowledgement Received

```
[Helmet] → [Helmet]                       : 15-second timer expired, no acknowledgement received                    : on timer expiry
[Helmet] → [Helmet]                       : power down, retain buffer storage                                       : immediately
```

> Helmet powers down without cloud acknowledgement. Buffer retained — data not lost.
>
> If shutdown message was received by cloud — processing continues as normal.
> If shutdown message was not received — LWT fires. Cloud treats as Flow 8 (Unexpected Dropout).
> When connectivity restores — smartphone syncs buffer including shutdown message.
> Cloud receives shutdown message retroactively — same resolution logic as Flow 6 Sad Path scenarios.

```
[Smartphone] → [Smartphone Local Storage] : retain buffered telemetry, shutdown message, helmet ID, timestamp       : immediately on helmet power down
[Smartphone] → [Telemetry Infrastructure — Catch-up Channel] : buffered telemetry, shutdown message, helmet ID, timestamp range : on connectivity restore
[Telemetry Infrastructure] → [Hot Storage] : buffered telemetry, shutdown message, helmet ID, timestamp range       : immediately
[Telemetry Infrastructure] → [SQS Control Queue] : shutdown message data point, helmet ID, timestamp                   : immediately
[Processing Infrastructure] → [SQS Control Queue] : read shutdown message data point                                   : event-driven
[Processing Infrastructure] → [Hot Storage] : query telemetry history for helmet ID                                 : immediately on reading data point from SQS
```

> Processing Infrastructure applies same resolution logic as Flow 6 Sad Path scenarios.

---

## Flow 8 — Unexpected Dropout / LWT

> **Precondition:** Rider is mid-ride. Smartphone disconnects from AWS IoT Core unexpectedly — no warning sent.
> LWT is registered at session startup. IoT Core fires it automatically on unexpected disconnect.

### LWT Fires

```
[AWS IoT Core] → [SQS LWT Queue]             : LWT message, helmet ID, last known timestamp        : on unexpected disconnection detected, via IoT Core rules engine
[Processing Infrastructure] → [SQS LWT Queue] : read LWT message, helmet ID, last known timestamp   : event-driven
[Processing Infrastructure] → [Processing Infrastructure] : start 5-second grace period timer, helmet ID           : immediately on LWT read
```

#### Sub-branch — Device Reconnects Within Grace Period

```
[Smartphone] → [AWS IoT Core]             : reconnection, helmet ID, timestamp                                      : within 5 seconds
[Processing Infrastructure] → [Processing Infrastructure] : discard LWT, device reconnected within grace period, helmet ID : on reconnection detected
```

> Normal telemetry resumes. No alert triggered. No log entry.
> Catch-up sync runs if backlog exists — same as Flow 2 Sad Path 2A.

#### Sub-branch — Device Does Not Reconnect Within Grace Period

```
[Processing Infrastructure] → [Processing Infrastructure] : grace period expired, no reconnection, treat as genuine unexpected dropout, helmet ID : on timer expiry
[Processing Infrastructure] → [Hot Storage] : query last telemetry for helmet ID                                    : immediately
[Hot Storage] → [Processing Infrastructure] : last telemetry payload                                                : immediately
[Processing Infrastructure] → [Processing Infrastructure] : analyse last telemetry for crash flag, helmet ID        : immediately
```

---

### Case 1 — No Crash Flag in Last Telemetry

```
[Processing Infrastructure] → [Processing Infrastructure] : no crash flag detected, mark helmet as unexpectedly offline, helmet ID, timestamp : immediately
[Processing Infrastructure] → [Cold Storage] : unexpected dropout log entry, helmet ID, last known timestamp, no crash flag, LWT fired : immediately
[Processing Infrastructure] → [Hot Storage] : start 24-hour retention window, helmet ID, last telemetry batch timestamp : immediately
```

> No alert triggered.

---

### Case 2 — Crash Flag Present in Last Telemetry

```
[Processing Infrastructure] → [Processing Infrastructure] : crash flag detected, run validation                     : immediately
[Processing Infrastructure] → [Hot Storage] : query recent telemetry history for helmet ID                         : immediately
[Hot Storage] → [Processing Infrastructure] : recent telemetry history                                              : immediately
[Processing Infrastructure] → [Processing Infrastructure] : validate crash event against telemetry history          : immediately
```

#### Sub-branch — Validated as False Positive

```
[Processing Infrastructure] → [Processing Infrastructure] : false positive confirmed, no alert to fire              : on validation result
[Processing Infrastructure] → [SQS Alert Queue]           : false positive confirmed, alert type — false_positive, helmet ID, crash timestamp, reason, LWT context : immediately
```

> No alert triggered.

#### Sub-branch — Validated as Genuine Crash

```
[Processing Infrastructure] → [Processing Infrastructure] : crash confirmed, proceed to alert                       : on validation result
[Processing Infrastructure] → [SQS Alert Queue]          : crash confirmed, alert type — standard, helmet ID, crash timestamp, incident location : immediately
```

> Alerting Infrastructure reads from SQS Alert Queue and applies alert type determination. See Flow 3 — Alerting Infrastructure Alert Type Determination.


> Helmet is gone — HUD notification may not be deliverable.
> Smartphone carries the countdown — 30 seconds acts as cancellation window.
> If smartphone or helmet comes back online within countdown — rider can cancel manually.

##### Rider Cancels from Smartphone Within Countdown

```
[Rider] → [Smartphone App]                        : cancel                                                          : within 30-second window
[Smartphone] → [AWS IoT Core]                     : publish cancel signal via MQTT                                  : immediately
[AWS IoT Core] → [Alerting Infrastructure]        : route cancel signal                                             : immediately
[Alerting Infrastructure] → [AWS IoT Core]        : publish dismiss countdown, helmet ID, timestamp                 : immediately
[AWS IoT Core] → [Smartphone]                     : dismiss countdown message via MQTT topic                        : immediately
[Smartphone App] → [Rider]                        : dismiss countdown                                               : immediately
[Alerting Infrastructure] → [Cold Storage]        : cancelled alert record, helmet ID, crash timestamp, cancelled by rider, LWT context : immediately
```

> No alert sent to Next of Kin or Emergency Services.

##### Rider Does Not Cancel — Alert Fires on Countdown Expiry

```
[Alerting Infrastructure] → [Next of Kin]         : crash alert, incident location, current location, incident timestamp : on countdown expiry
[Alerting Infrastructure] → [Emergency Services]  : crash alert, incident location, current location, incident timestamp, next of kin contact : on countdown expiry, independent of Next of Kin channel
[Alerting Infrastructure] → [Cold Storage]        : incident record, helmet ID, crash timestamp, incident location, delivery outcome per channel : on resolution
```

---

### Smartphone Unreachable During Countdown

> Cloud runs countdown anyway — no cancel signal received.

```
[Alerting Infrastructure] → [Alerting Infrastructure] : countdown expired, no cancel signal received, smartphone unreachable : on countdown expiry
[Alerting Infrastructure] → [Next of Kin]         : crash alert, incident location, current location, incident timestamp : immediately
[Alerting Infrastructure] → [Emergency Services]  : crash alert, incident location, current location, incident timestamp, next of kin contact : immediately, independent of Next of Kin channel
[Alerting Infrastructure] → [Cold Storage]        : incident record, helmet ID, crash timestamp, incident location, smartphone unreachable at time of alert, delivery outcome per channel : on resolution
```

#### Smartphone Comes Back Online After Alert Already Fired

> Follows same retroactive resolution logic as Flow 6 Scenario 2B.

```
[Smartphone App] → [Rider]                : "Next of Kin and Emergency Services have been alerted — do you want to notify them the rider is safe?" : on smartphone reconnection
```

> Rider confirms or declines — same flow as Flow 6 Scenario 2B.

---

## Flow 9 — Mass Alert and Infrastructure Failure Detection

> **Purpose:** This flow covers how the system detects, responds to, and recovers from infrastructure failures across all layers — device, cloud, config, and observability. It also covers how the system distinguishes a real mass incident from a firmware bug or infrastructure misclassification when a large number of simultaneous crash alerts are received.
>
> **Sub-flows:**
>
> | # | Sub-flow | Status |
> |---|---|---|
> | 9A | Monitoring Stack and Detection | ✅ Complete |
> | 9B | Sensor Failure (device layer) | ✅ Complete |
> | 9C | Helmet Telemetry to Smartphone Failure (device layer) | ✅ Complete |
> | 9D | Smartphone Telemetry to Cloud Failure (device layer) | ✅ Complete |
> | 9E | IoT Core / MQTT Broker Failure (cloud layer) | ✅ Complete |
> | 9F | Telemetry Infrastructure Failure (cloud layer) | ✅ Complete |
> | 9G | Processing Infrastructure Failure (cloud layer) | ✅ Complete |
> | 9H | Alerting Infrastructure Failure (cloud layer) | ✅ Complete |
> | 9I | Database Failure (cloud layer) | ✅ Complete |
> | 9J | Parameter Store Unavailability (config layer) | ⬜ Pending |
> | 9K | Bad Firmware Update (config layer) | ⬜ Pending |
> | 9L | Bad Infrastructure Deploy — CI/CD Pipeline (config layer) | ⬜ Pending |
> | 9M | Monitoring Stack Failure (observability layer) | ⬜ Pending |

---

## Flow 9A — Monitoring Stack and Detection

> **Purpose:** This flow defines the detection and alerting chain that underpins all subsequent Flow 9 sub-flows. Every infrastructure failure scenario in Flows 9B onward references this flow for how failures are detected and how engineers are notified.
>
> **Monitoring stack:** Prometheus + Alertmanager + Grafana running on ECS Fargate. CloudWatch + SNS used for AWS-native services (IoT Core, Database). PagerDuty is the single paging destination for all alerts regardless of which monitoring path fired.
>
> **Dead man's switch:** Monitoring Infrastructure sends a heartbeat ping to Healthchecks.io every 60 seconds. If the heartbeat stops, Healthchecks.io pages the Infrastructure Engineer via PagerDuty independently of the monitoring stack itself.
>
> **Firmware version field:** All telemetry payloads include a firmware version field. This enables Processing Infrastructure to correlate mass alert spikes against specific firmware versions during incident triage.

---

### Continuous Health Checks

```
[Prometheus] → [Telemetry Infrastructure]          : /health endpoint scrape                                        : every 60 seconds
[Prometheus] → [Processing Infrastructure]         : /health endpoint scrape                                        : every 60 seconds
[Prometheus] → [Alerting Infrastructure]           : /health endpoint scrape                                        : every 60 seconds
[Prometheus] → [Database — Hot Storage]            : /health endpoint scrape                                        : every 60 seconds
[Prometheus] → [Database — Cold Storage]           : /health endpoint scrape                                        : every 60 seconds
[Prometheus] → [CI/CD Pipeline]                    : /health endpoint scrape                                        : every 60 seconds
[Prometheus] → [SQS Crash Queue]                   : queue depth, message age, dead letter queue count              : every 60 seconds
[Prometheus] → [SQS Control Queue]                 : queue depth, message age, dead letter queue count              : every 60 seconds
[Prometheus] → [SQS LWT Queue]                     : queue depth, message age, dead letter queue count              : every 60 seconds
[Prometheus] → [SQS Alert Queue]                   : queue depth, message age, dead letter queue count              : every 60 seconds
[CloudWatch] → [IoT Core]                          : health and performance metrics scrape                          : every 30 seconds
```

---

### Continuous Metric Scraping

```
[Prometheus] → [Telemetry Infrastructure]          : CPU, memory, queue depth, message throughput                   : every 60 seconds
[Prometheus] → [Processing Infrastructure]         : CPU, memory, queue depth, processing latency                   : every 60 seconds
[Prometheus] → [Alerting Infrastructure]           : CPU, memory, active alert count, delivery latency              : every 60 seconds
[Prometheus] → [Database — Hot Storage]            : CPU, memory, write latency, storage utilisation                : every 60 seconds
[Prometheus] → [Database — Cold Storage]           : CPU, memory, write latency, storage utilisation                : every 60 seconds
[Prometheus] → [SQS LWT Queue]                     : queue depth, DLQ depth, message age                            : every 60 seconds
[Prometheus] → [SQS Alert Queue]                   : queue depth, DLQ depth, message age                            : every 60 seconds
[CloudWatch] → [IoT Core]                          : connection count, message rate, error rate                      : every 30 seconds
```

---

### Dead Man's Switch

```
[Monitoring Infrastructure] → [Healthchecks.io]   : heartbeat ping                                                  : every 60 seconds
[Healthchecks.io] → [Healthchecks.io]             : check heartbeat received within expected window                  : every 60 seconds
```

#### Sub-branch — Heartbeat Stops

```
[Healthchecks.io] → [PagerDuty]                   : monitoring infrastructure unreachable, timestamp                 : on missed heartbeat
[PagerDuty] → [Infrastructure Engineer]           : page — monitoring infrastructure down, timestamp                 : immediately via SMS and call
```

---

### Threshold Breach Detection

```
[Prometheus] → [Prometheus]                        : evaluate all scraped metrics against threshold rules             : on every scrape
[CloudWatch] → [CloudWatch]                        : evaluate IoT Core metrics against alarm thresholds               : on every scrape
```

#### Sub-branch — Threshold Breached or Component Unreachable (Prometheus path)

```
[Prometheus] → [Alertmanager]                      : alert fired, component, metric, threshold breached, timestamp    : immediately
[Alertmanager] → [Alertmanager]                    : deduplicate and group alerts by component and failure type        : immediately
[Alertmanager] → [PagerDuty]                       : grouped alert, component, failure type, severity, timestamp      : immediately
[PagerDuty] → [Infrastructure Engineer]            : page — component degraded or unreachable, details, timestamp     : immediately via SMS and call
```

#### Sub-branch — Threshold Breached (CloudWatch path)

```
[CloudWatch] → [SNS]                               : alarm triggered, component, metric, threshold breached, timestamp : immediately
[SNS] → [PagerDuty]                                : alarm details, component, timestamp                               : immediately
[PagerDuty] → [Infrastructure Engineer]            : page — IoT Core degraded or unreachable, details, timestamp      : immediately via SMS and call
```

---

### Grafana Dashboard

```
[Grafana] → [Prometheus]                           : query all component metrics                                      : continuously
[Grafana] → [CloudWatch]                           : query IoT Core and DB metrics                                    : continuously
[Grafana] → [Infrastructure Engineer]              : live dashboard — all component health, metrics, active alerts    : available at all times
```

---

### Mass Alert Threshold Detection

> Mass alert threshold value stored in Parameter Store. Read by Processing Infrastructure at startup.

```
[Processing Infrastructure] → [Processing Infrastructure] : count simultaneous crash alerts across fleet              : continuously
[Processing Infrastructure] → [Processing Infrastructure] : compare active alert count against mass alert threshold   : on every crash event received
```

#### Sub-branch — Threshold Crossed

```
[Processing Infrastructure] → [Processing Infrastructure] : mass alert threshold crossed — run decision tree          : immediately
```

---

### Mass Alert Decision Tree

#### Step 1 — Geographic Distribution Check

```
[Processing Infrastructure] → [Processing Infrastructure] : check geographic distribution of alerts across fleet      : immediately on threshold crossed
```

##### Branch A — Alerts Geographically Clustered

```
[Processing Infrastructure] → [Processing Infrastructure] : clustered alerts — likely real mass incident              : on clustering confirmed
[Processing Infrastructure] → [Alerting Infrastructure]   : proceed with alerts, mass incident flag, timestamp        : immediately
[Alerting Infrastructure] → [PagerDuty]                   : mass incident in progress, alert volume spike, timestamp  : immediately
[PagerDuty] → [Infrastructure Engineer]                   : page — mass incident in progress, monitor infra load      : immediately via SMS and call
```

> Alerts fire normally. No alerts held. Engineer monitors infrastructure load during mass event.

##### Branch B — Alerts Geographically Dispersed

```
[Processing Infrastructure] → [Processing Infrastructure] : dispersed alerts — likely firmware bug or infra failure — proceed to firmware version check : immediately
```

---

#### Step 2 — Firmware Version Correlation Check

> Only runs if alerts are geographically dispersed.

```
[Processing Infrastructure] → [Processing Infrastructure] : check firmware version field across all alerting helmets  : immediately
```

##### Branch B1 — Alerts Correlated to Specific Firmware Version

```
[Processing Infrastructure] → [Processing Infrastructure] : firmware version correlation confirmed — likely firmware bug : immediately
[Processing Infrastructure] → [Alerting Infrastructure]   : hold all dispersed alerts pending Fleet Manager review, helmet IDs, firmware version, timestamp : immediately
[Alerting Infrastructure] → [PagerDuty]                   : mass alert spike correlated to firmware version, helmet IDs, firmware version, timestamp : immediately
[PagerDuty] → [Fleet Manager]                             : page — possible firmware bug, rollback may be required, timestamp : immediately via SMS and call
```

> Alerts held. Fleet Manager investigates. Rollback decision owned by Fleet Manager — see Flow 10.

##### Branch B2 — Alerts Span All Firmware Versions

```
[Processing Infrastructure] → [Processing Infrastructure] : no firmware version correlation — likely Processing Infra misclassification : immediately
[Processing Infrastructure] → [Alerting Infrastructure]   : hold all dispersed alerts pending Infrastructure Engineer review, timestamp : immediately
[Alerting Infrastructure] → [PagerDuty]                   : mass alert spike, no firmware correlation, possible infra misclassification, timestamp : immediately
[PagerDuty] → [Infrastructure Engineer]                   : page — possible Processing Infra failure, all dispersed alerts held, immediate investigation required : immediately via SMS and call
```

> All dispersed alerts held. Infrastructure Engineer investigates Processing Infra before any alerts are released or discarded.

---

### Alert Routing Summary

| Failure Type | Notified Via | Recipient |
|---|---|---|
| Any cloud infra component degraded or unreachable | PagerDuty | Infrastructure Engineer |
| IoT Core degraded or unreachable | CloudWatch → SNS → PagerDuty | Infrastructure Engineer |
| Monitoring Infrastructure down | Healthchecks.io → PagerDuty | Infrastructure Engineer |
| Mass alert — firmware version correlated | PagerDuty | Fleet Manager |
| Mass alert — no firmware correlation, infra suspected | PagerDuty | Infrastructure Engineer |
| Mass alert — geographically clustered, real incident | PagerDuty | Infrastructure Engineer (load monitoring) |

---

## Flow 9B — Sensor Failure (Device Layer)

> **Precondition:** Helmet is active mid-ride. One or more helmet sensors begin producing garbage telemetry — values that are out of range, corrupted, or generating false crash flags at the edge processing layer.
>
> **Single helmet sensor failure** — Processing Infrastructure's false positive validation logic catches garbage telemetry from an individual helmet and generates a maintenance flag. This is covered in Flow 1 Branch B and Flow 3 Branch A. No new infrastructure behaviour is introduced for a single helmet.
>
> **Fleet-wide sensor failure** — A firmware bug causes many helmets simultaneously to produce false crash flags. This crosses the mass alert threshold in Flow 9A and enters the decision tree defined there. Flow 9B documents the full resolution path from that point onward.
>
> **Reference:** Single helmet sensor failure → see Flow 1 Branch B (maintenance flag) and Flow 3 Branch A (false positive handling). Fleet-wide sensor failure enters via Flow 9A Branch B1 (firmware version correlated mass alert).

---

### Rider Notification During Hold Period

> Triggered when Processing Infrastructure holds alerts and Fleet Manager is paged. Riders mid-ride are notified immediately on both devices.

```
[Processing Infrastructure] → [Alerting Infrastructure]   : hold all dispersed alerts, fleet-wide issue detected, firmware version, timestamp          : immediately on hold initiated
[Alerting Infrastructure] → [AWS IoT Core]                : publish maintenance notification, all affected helmet IDs, timestamp                        : immediately
[AWS IoT Core] → [Smartphone]                             : maintenance message via MQTT topic                                                          : immediately to all affected smartphones
[Smartphone App] → [Rider]                                : "Fleet-wide issue detected — alert systems under maintenance, please ride with caution"     : immediately
[Smartphone] → [Helmet HUD]                               : forward maintenance message via Bluetooth                                                   : immediately
[Helmet HUD] → [Rider]                                    : "Fleet-wide issue detected — alert systems under maintenance"                               : immediately
```

> Alert systems are in maintenance mode for all affected helmets during the hold window. No alerts fire during this period.

---

### Fleet Manager Investigation and Resolution

```
[Fleet Manager] → [Fleet Management System]               : investigate mass alert spike, firmware version, helmet IDs, timestamp                       : on receiving PagerDuty page
[Fleet Management System] → [Fleet Manager]               : fleet status, firmware version distribution, affected helmet count, alert event log         : immediately
```

---

### Outcome 1 — Firmware Bug Confirmed, Rollback Initiated

> Fleet Manager confirms the firmware version is the cause. Rollback is initiated via the firmware pipeline — see Flow 10.

```
[Fleet Manager] → [Fleet Management System]               : confirm firmware bug, initiate rollback, firmware version, timestamp                        : on investigation complete
[Fleet Management System] → [Processing Infrastructure]   : firmware bug confirmed, discard all held alerts for affected firmware version, timestamp    : immediately
[Processing Infrastructure] → [SQS Alert Queue]           : false positive confirmed, alert type — false_positive, reason — firmware bug confirmed, helmet IDs, firmware version : immediately per held alert
[Alerting Infrastructure] → [Cold Storage]                : false positive log entry per held alert, helmet ID, crash timestamp, reason — firmware bug confirmed, firmware version, discarded at : immediately on read
[Alerting Infrastructure] → [AWS IoT Core]                : publish issue resolved notification, all affected helmet IDs, timestamp                     : immediately
[AWS IoT Core] → [Smartphone]                             : issue resolved message via MQTT topic                                                       : immediately to all affected smartphones
[Smartphone App] → [Rider]                                : "Fleet-wide issue resolved — alert systems restored"                                        : immediately
[Smartphone] → [Helmet HUD]                               : forward issue resolved message via Bluetooth                                                : immediately
[Helmet HUD] → [Rider]                                    : "Fleet-wide issue resolved — alert systems restored"                                        : immediately
```

> No alerts fired. All held alert events written to cold storage with firmware bug remark. Riders informed systems are restored.

---

### Outcome 2 — No Firmware Bug Found, Held Alerts May Be Genuine

> Fleet Manager investigation finds no firmware cause. Held alerts are returned to Processing Infrastructure for individual re-validation.

```
[Fleet Manager] → [Fleet Management System]               : no firmware bug found, release held alerts for re-validation, timestamp                     : on investigation complete
[Fleet Management System] → [Processing Infrastructure]   : release held alerts, helmet IDs, held alert timestamps                                      : immediately
[Processing Infrastructure] → [Processing Infrastructure] : re-validate each held alert individually against available telemetry                        : immediately on release
```

#### Sub-branch — Held Alert Under 24 Hours (Hot Storage Data Available)

```
[Processing Infrastructure] → [Hot Storage]               : query recent telemetry for helmet ID                                                        : on each held alert re-validation
[Hot Storage] → [Processing Infrastructure]               : telemetry history                                                                           : immediately
[Processing Infrastructure] → [Processing Infrastructure] : validate crash event against telemetry history                                              : immediately
```

##### Validated as False Positive

```
[Processing Infrastructure] → [SQS Alert Queue]           : false positive confirmed, alert type — false_positive, helmet ID, crash timestamp, reason, held alert context : immediately
```

> No alert fired.

##### Validated as Genuine Crash

```
[Processing Infrastructure] → [SQS Alert Queue]           : crash confirmed, alert type — standard, helmet ID, crash timestamp, incident location       : immediately
```

> Alerting Infrastructure reads from SQS Alert Queue and applies alert type determination. See Flow 3 — Alerting Infrastructure Alert Type Determination.

> Full Flow 3 alert countdown runs unmodified from this point. See Flow 3 — Alert Countdown.

---

#### Sub-branch — Held Alert Over 24 Hours (No Hot Storage Data Available)

> Hot storage retention window has expired. Processing Infrastructure has no telemetry to validate against. Decision goes to rider — same mechanic as Flow 4 Retrospective Alert.

```
[Processing Infrastructure] → [Hot Storage]               : query recent telemetry for helmet ID                                                        : on re-validation attempt
[Hot Storage] → [Processing Infrastructure]               : no data found — retention window expired                                                    : immediately
[Processing Infrastructure] → [SQS Alert Queue]           : cannot validate — alert type — retrospective, helmet ID, crash timestamp, incident location from held alert : immediately
```

> Alerting Infrastructure reads from SQS Alert Queue. Label is retrospective — persistent notification shown immediately.

```
[Alerting Infrastructure] → [AWS IoT Core]                : publish persistent notification, helmet ID, timestamp                                       : immediately
[AWS IoT Core] → [Smartphone]                             : persistent notification message via MQTT topic                                              : immediately
[Smartphone App] → [Rider]                                : persistent notification — "A crash alert from [timestamp] could not be verified — do you want to alert emergency services?" : immediately
[Smartphone] → [Helmet HUD]                               : forward persistent notification via Bluetooth                                               : immediately
[Helmet HUD] → [Rider]                                    : persistent notification — "Crash alert from [timestamp] unverified — see smartphone app"    : immediately if helmet still online
```

##### Rider Confirms

```
[Rider] → [Smartphone App or Helmet HUD]                  : confirm                                                                                     : on rider action
[Smartphone] → [AWS IoT Core]                             : publish confirm signal via MQTT                                                             : immediately
[AWS IoT Core] → [Alerting Infrastructure]                : route confirm signal                                                                        : immediately
[Alerting Infrastructure] → [Next of Kin]                 : crash alert, incident location from held alert, current location, incident timestamp        : immediately
[Alerting Infrastructure] → [Emergency Services]          : crash alert, incident location from held alert, current location, incident timestamp, next of kin contact : immediately, independent of Next of Kin channel
[Alerting Infrastructure] → [Cold Storage]                : incident record, helmet ID, crash timestamp, incident location, confirmed by rider after hold expiry, delivery outcome per channel : on resolution
```

##### Rider Cancels

```
[Rider] → [Smartphone App or Helmet HUD]                  : cancel                                                                                      : on rider action
[Smartphone] → [AWS IoT Core]                             : publish cancel signal via MQTT                                                              : immediately
[AWS IoT Core] → [Alerting Infrastructure]                : route cancel signal                                                                         : immediately
[Alerting Infrastructure] → [AWS IoT Core]                : publish dismiss notification, helmet ID, timestamp                                          : immediately
[AWS IoT Core] → [Smartphone]                             : dismiss notification message via MQTT topic                                                 : immediately
[Smartphone App] → [Rider]                                : dismiss notification                                                                        : immediately
[Smartphone] → [Helmet HUD]                               : forward dismiss notification via Bluetooth                                                  : immediately
[Helmet HUD] → [Rider]                                    : dismiss notification                                                                        : immediately
[Alerting Infrastructure] → [Cold Storage]                : cancelled alert record, helmet ID, crash timestamp, cancelled by rider after hold expiry     : immediately
```

> No alert fired.

##### Rider Unreachable

```
[Alerting Infrastructure] → [Alerting Infrastructure]     : no rider response, smartphone unreachable                                                   : on notification delivery failure
[Alerting Infrastructure] → [Cold Storage]                : unresolved alert record, helmet ID, crash timestamp, incident location, rider unreachable, no alert fired : immediately
```

> No alert fired. Incident logged to cold storage for Fleet Manager review.

---

## Flow 9C — Helmet Telemetry to Smartphone Failure (Device Layer)

> **Precondition:** Rider is mid-ride. Helmet and Smartphone are paired and telemetry is flowing normally. Bluetooth link between Helmet and Smartphone drops unexpectedly.
>
> **Note:** This flow covers mid-ride Bluetooth failure only. Bluetooth failure at startup (before pairing is established) is covered in Flow 2 Sad Path 1.
>
> **Note:** LWT does not fire in this flow. The Smartphone remains connected to IoT Core throughout — only the Bluetooth link to the Helmet is lost. The Smartphone actively publishes the disconnection event itself.

---

### Bluetooth Link Drops

```
[Helmet] → [Helmet]                       : bluetooth link lost, no smartphone connection detected                  : immediately on disconnection
[Helmet] → [Helmet]                       : retain all telemetry in buffer, do not clear                            : immediately
[Helmet HUD] → [Rider]                    : "Bluetooth disconnected — telemetry and alert systems offline"          : immediately

[Smartphone] → [Smartphone]               : bluetooth link lost, helmet disconnected                                : immediately on disconnection
[Smartphone] → [Smartphone Local Storage] : discard partial telemetry batch (incomplete 10-second window)           : immediately — helmet buffer retains full data, no data lost
[Smartphone App] → [Rider]                : "Helmet disconnected — telemetry and alert systems offline"             : immediately
```

---

### Smartphone Notifies Cloud

```
[Smartphone] → [AWS IoT Core]             : bluetooth disconnected event, helmet ID, timestamp                      : immediately via helmet/{helmet_id}/bluetooth_disconnected topic
[AWS IoT Core] → [Processing Infrastructure] : bluetooth disconnected event, helmet ID, timestamp                   : immediately via IoT Core rules engine
[Processing Infrastructure] → [Processing Infrastructure] : check last telemetry for crash flag, helmet ID          : immediately on bluetooth disconnected event received
```

---

### Branch A — No Crash Flag in Last Telemetry

```
[Processing Infrastructure] → [Processing Infrastructure] : no crash flag detected, mark helmet as bluetooth disconnected, helmet ID, timestamp : immediately
[Processing Infrastructure] → [Cold Storage]              : bluetooth disconnected log entry, helmet ID, last known timestamp, no crash flag    : immediately
```

> No alert triggered.

---

### Branch B — Crash Flag Present in Last Telemetry

> Validation and alert mechanics identical to Flow 8 Case 2. See Flow 8 — Case 2 — Crash Flag Present in Last Telemetry.

---

### Helmet Continues Operating — Buffer Only

```
[Helmet Sensors] → [Helmet]               : accelerometer, speed, edge result, helmet ID, timestamp                 : every 1 second
[Helmet] → [Helmet]                       : store all telemetry in buffer                                           : every 1 second
```

---

### On Bluetooth Restore

```
[Helmet] → [Smartphone]                   : bluetooth reconnection, helmet ID, timestamp                            : on link restore
[Smartphone] → [Helmet]                   : pairing confirmation                                                    : immediately
[Smartphone App] → [Rider]                : "Helmet reconnected — telemetry and alert systems restored"             : immediately
[Helmet HUD] → [Rider]                    : "Bluetooth restored — systems operational"                              : immediately

[Smartphone] → [AWS IoT Core]             : bluetooth restored event, helmet ID, timestamp                          : immediately via helmet/{helmet_id}/bluetooth_restored topic
[AWS IoT Core] → [Processing Infrastructure] : bluetooth restored event, helmet ID, timestamp                       : immediately via IoT Core rules engine
[Processing Infrastructure] → [Processing Infrastructure] : mark helmet as bluetooth restored, helmet ID, timestamp : immediately
```

---

### Catch-Up Sync on Restore

> Backlog flush mechanics identical to Flow 2 Sad Path 2A. See Flow 2 Sad Path 2A — Backlog Flush via Catch-Up Channel.

```
[Telemetry Infrastructure] → [Hot Storage]               : synced buffered data, helmet ID, timestamp range         : on each acknowledged chunk
[Telemetry Infrastructure] → [Telemetry Infrastructure]  : inspect synced chunk for crash flag                      : immediately
[Telemetry Infrastructure] → [SQS Crash Queue]           : crash event data point, helmet ID, timestamp                : if crash flag found in chunk
[Processing Infrastructure] → [SQS Crash Queue]          : read crash event data point                                  : event-driven
[Processing Infrastructure] → [Processing Infrastructure] : scan for crash flag in synced data                      : immediately on reading data point from SQS
```

---

### Branch C — No Crash Flag in Synced Data

> Catch-up sync completes normally. No alert triggered.

---

### Branch D — Crash Flag Detected in Synced Data

> Retrospective alert mechanic runs. Identical to Flow 4 Retrospective Alert. See Flow 4 — Retrospective Alert.

---

## Flow 9D — Smartphone Telemetry to Cloud Failure (Device Layer)

> **Architecture note:** All prior flows that show `[Smartphone] → [Telemetry Infrastructure]` represent the logical data path. The actual transport layer is `Smartphone → AWS IoT Core (MQTT) → IoT Rules Engine → Telemetry Infrastructure`. IoT Core sits implicitly in every one of those arrows. Flow 9E covers IoT Core failure specifically.

> **Precondition:** Rider is mid-ride. Bluetooth between Helmet and Smartphone is active. Smartphone is unable to publish telemetry to the cloud.

> **Scenarios covered:**
>
> | Scenario | Handling |
> |---|---|
> | Loss of internet | See Flow 2 Sad Path 2A — behaviour is identical mid-ride |
> | Telemetry Infrastructure unreachable | See Flow 2 Sad Path 2B — behaviour is identical mid-ride |
> | IoT Core / MQTT broker failure | See Flow 9E |
> | Smartphone device failure | Out of scope — cloud detects silence, Flow 8 runs |
> | Smartphone app failure | Out of scope — cloud detects silence, Flow 8 runs |

> **No new infrastructure behaviour is introduced in this flow.** All failure modes either reference existing flows or fall outside the infrastructure scope of this project.

---

## Flow 9E — IoT Core / MQTT Broker Failure (Cloud Layer)

> **Precondition:** Rider is mid-ride. Bluetooth between Helmet and Smartphone is active. IoT Core becomes unreachable — either due to internet loss on the smartphone side or IoT Core itself going down.
>
> **Known limitation:** IoT Core is the MQTT broker responsible for firing LWT messages on unexpected helmet dropout. If IoT Core is down, LWT cannot fire. Any crash that occurs during an IoT Core outage will not trigger an LWT-based alert. The crash event will be captured in the helmet and smartphone buffers and processed retrospectively when IoT Core recovers — same mechanic as Flow 4 Retrospective Alert.
>
> **Data collection during outage:** Helmet continues sensing and sending to smartphone every second. Smartphone continues buffering locally. Collection never pauses — only upload to cloud is interrupted. Catch-up pipeline flushes backlog on restore.

---

### Smartphone Detects IoT Core Unreachable

```
[Smartphone] → [Smartphone]               : attempt to reach IoT Core endpoint                                      : on connectivity check
[Smartphone] → [Smartphone]               : IoT Core endpoint unreachable                                           : on failed connection attempt
```

---

### Branch A — Internet Loss (Smartphone Cannot Reach Anything)

```
[Smartphone] → [Smartphone]               : internet unreachable, not an IoT Core specific failure                  : on connectivity check
[Smartphone App] → [Rider]                : "Network failure — telemetry and alert systems not operational"          : immediately
[Helmet HUD] → [Rider]                    : "Network failure — telemetry and alert systems not operational"          : immediately
```

> Smartphone buffers locally. Helmet continues sensing and buffering. See Flow 2 Sad Path 2A for full buffering and catch-up pipeline behaviour.

---

### Branch B — IoT Core Down (Smartphone Has Internet, IoT Core Endpoint Unreachable)

```
[Smartphone] → [Smartphone]               : internet reachable, IoT Core endpoint unreachable — IoT Core down       : on connectivity check
[Smartphone App] → [Rider]                : "Alert system failure — this is not a device issue, please ride with caution" : immediately
[Helmet HUD] → [Rider]                    : "Alert system failure — this is not a device issue, please ride with caution" : immediately
```

> Smartphone buffers locally. Helmet continues sensing and buffering. See Flow 2 Sad Path 2A for full buffering and catch-up pipeline behaviour.

---

### Cloud Side — Monitoring Detects IoT Core Failure

```
[CloudWatch] → [IoT Core]                          : health and performance metrics scrape                          : every 30 seconds
[IoT Core] → [CloudWatch]                          : no response                                                    : —
[CloudWatch] → [SNS]                               : alarm triggered, IoT Core unreachable, timestamp               : immediately
[SNS] → [PagerDuty]                                : alarm details, IoT Core unreachable, timestamp                 : immediately
[PagerDuty] → [Infrastructure Engineer]            : page — IoT Core down, timestamp                                : immediately via SMS and call
```

> See Flow 9A — Alert Routing for full monitoring chain.

---

### On IoT Core Recovery

```
[Smartphone] → [Smartphone]               : IoT Core endpoint reachable                                             : on periodic connectivity check
[Smartphone] → [AWS IoT Core]             : reconnect, re-register LWT, helmet ID, timestamp                        : immediately on IoT Core reachable
[AWS IoT Core] → [Smartphone]             : connection confirmed, LWT registered                                     : immediately
[Smartphone App] → [Rider]                : "Alert system restored — telemetry operational"                         : immediately
[Helmet HUD] → [Rider]                    : "Alert system restored — telemetry operational"                         : immediately
```

> LWT re-registration happens automatically as part of MQTT reconnection. No special infrastructure configuration required.

---

### Catch-Up Sync on Recovery

> Backlog flush mechanics identical to Flow 2 Sad Path 2A. See Flow 2 Sad Path 2A — Backlog Flush via Catch-Up Channel.

```
[Telemetry Infrastructure] → [Hot Storage]               : synced buffered data, helmet ID, timestamp range         : on each acknowledged chunk
[Telemetry Infrastructure] → [Telemetry Infrastructure]  : inspect synced chunk for crash flag                      : immediately
[Telemetry Infrastructure] → [SQS Crash Queue]           : crash event data point, helmet ID, timestamp                : if crash flag found in chunk
[Processing Infrastructure] → [SQS Crash Queue]          : read crash event data point                                  : event-driven
[Processing Infrastructure] → [Processing Infrastructure] : scan for crash flag in synced data                      : immediately on reading data point from SQS
```

---

### Branch C — No Crash Flag in Synced Data

> Catch-up sync completes normally. No alert triggered.

---

### Branch D — Crash Flag Detected in Synced Data

> Retrospective alert mechanic runs. Identical to Flow 4 Retrospective Alert. See Flow 4 — Retrospective Alert.

---

## Flow 9F — Telemetry Infrastructure Failure (Cloud Layer)

> **Precondition:** Rider is mid-ride. Bluetooth between Helmet and Smartphone is active. Smartphone is connected to AWS IoT Core. Telemetry Infrastructure becomes unavailable. IoT Core is still up — the MQTT session between Smartphone and IoT Core remains intact throughout.
>
> **Known limitation:** Real-time crash alerts cannot fire during a Telemetry Infrastructure outage. Telemetry Infrastructure is the service that writes crash data points to SQS Crash Queue. With it down, no new crash events reach Processing Infrastructure. Any crash that occurs during the outage is captured in the Smartphone buffer and processed retrospectively when Telemetry Infrastructure recovers — same mechanic as Flow 4 Retrospective Alert.
>
> **New infrastructure:** `helmet/{helmet_id}/infra/status` — cloud-to-device MQTT topic published by Monitoring Infrastructure via IoT Core. Smartphone subscribes at session startup (see Flow 1 — Cloud Connectivity Check). Provisioned in Terraform alongside all other topics. Monitoring Infrastructure IAM policy scoped to publish on `helmet/*/infra/status`.

---

### Monitoring Stack Detects Telemetry Infrastructure Failure

```
[Prometheus] → [Telemetry Infrastructure]          : /health endpoint scrape                                        : every 60 seconds
[Telemetry Infrastructure] → [Prometheus]          : no response                                                    : —
[Prometheus] → [Alertmanager]                      : alert fired, Telemetry Infrastructure unreachable, timestamp   : on health check failure threshold crossed
[Alertmanager] → [PagerDuty]                       : Telemetry Infrastructure down, timestamp                       : immediately
[PagerDuty] → [Infrastructure Engineer]            : page — Telemetry Infrastructure down, timestamp                : immediately via SMS and call
```

> See Flow 9A — Threshold Breach Detection for full monitoring chain.

---

### Rider Notification

```
[Monitoring Infrastructure] → [AWS IoT Core]       : publish infra down status, helmet ID, timestamp               : once per active helmet, on failure confirmed
[AWS IoT Core] → [Smartphone]                      : infra down status message                                      : via helmet/{helmet_id}/infra/status topic
[Smartphone App] → [Rider]                         : "Alert system failure — this is not a device issue, please ride with caution" : immediately
[Smartphone] → [Helmet HUD]                        : infra down status, helmet ID, timestamp                        : immediately via Bluetooth
[Helmet HUD] → [Rider]                             : "Alert system failure — this is not a device issue, please ride with caution" : immediately
```

> Smartphone MQTT session remains active — no reconnection required. IoT Core is up. One status message published per active helmet — not one per failed delivery.

---

### Device Behaviour During Outage

```
[Helmet Sensors] → [Helmet]               : accelerometer, speed, edge result, helmet ID, timestamp                 : every 1 second
[Helmet] → [Smartphone]                   : telemetry payload, helmet ID, timestamp                                 : every 1 second
[Smartphone] → [Smartphone Local Storage] : telemetry payload                                                       : every 1 second until Telemetry Infrastructure restores
```

> Helmet and Smartphone continue operating normally. All telemetry buffered locally on Smartphone. No data is lost.

---

### Processing Infrastructure Behaviour During Outage

> Telemetry Infrastructure is the only service that writes to SQS Crash Queue and SQS Control Queue. With it down, no new events enter either queue. Processing Infrastructure is not failed — it continues to drain any crash or control events that were already in the queues before the failure. Once those are consumed, Processing Infrastructure goes idle and waits. Pre-failure crash events in the queue have their corresponding telemetry already written to hot storage and are processed normally.

```
[Processing Infrastructure] → [SQS Crash Queue]    : read any pre-failure crash event data points                      : event-driven, until queue is empty
[Processing Infrastructure] → [SQS Control Queue]  : read any pre-failure control event data points                    : event-driven, until queue is empty
```

> No alert mechanics change for pre-failure crash events. Hot storage data written before the failure is available and valid for validation.

---

### On Telemetry Infrastructure Recovery

```
[Prometheus] → [Telemetry Infrastructure]          : /health endpoint scrape                                        : every 60 seconds
[Telemetry Infrastructure] → [Prometheus]          : health check passed                                            : on recovery
[Prometheus] → [Alertmanager]                      : alert resolved, Telemetry Infrastructure restored, timestamp   : immediately
[Alertmanager] → [PagerDuty]                       : Telemetry Infrastructure restored, timestamp                   : immediately
[PagerDuty] → [Infrastructure Engineer]            : Telemetry Infrastructure restored, timestamp                   : immediately
[Monitoring Infrastructure] → [AWS IoT Core]       : publish infra restored status, helmet ID, timestamp           : once per active helmet, on recovery confirmed
[AWS IoT Core] → [Smartphone]                      : infra restored status message                                  : via helmet/{helmet_id}/infra/status topic
[Smartphone App] → [Rider]                         : "Alert system restored — telemetry operational"               : immediately
[Smartphone] → [Helmet HUD]                        : infra restored status, helmet ID, timestamp                   : immediately via Bluetooth
[Helmet HUD] → [Rider]                             : "Alert system restored — telemetry operational"               : immediately
```

---

### Catch-Up Sync on Recovery

> Backlog flush mechanics identical to Flow 2 Sad Path 2A. See Flow 2 Sad Path 2A — Backlog Flush via Catch-Up Channel.

```
[Telemetry Infrastructure] → [Hot Storage]               : synced buffered data, helmet ID, timestamp range         : on each acknowledged chunk
[Telemetry Infrastructure] → [Telemetry Infrastructure]  : inspect synced chunk for crash flag                      : immediately
[Telemetry Infrastructure] → [SQS Crash Queue]           : crash event data point, helmet ID, timestamp                : if crash flag found in chunk
[Processing Infrastructure] → [SQS Crash Queue]          : read crash event data point                                  : event-driven
[Processing Infrastructure] → [Processing Infrastructure] : scan for crash flag in synced data                      : immediately on reading data point from SQS
```

---

### Branch C — No Crash Flag in Synced Data

> Catch-up sync completes normally. No alert triggered.

---

### Branch D — Crash Flag Detected in Synced Data

> Retrospective alert mechanic runs. Identical to Flow 4 Retrospective Alert. See Flow 4 — Retrospective Alert.

## Flow 9G — Processing Infrastructure Failure (Cloud Layer)

> **Precondition:** Rider is mid-ride. Bluetooth between Helmet and Smartphone is active. Smartphone is connected to AWS IoT Core. Telemetry Infrastructure is up. Processing Infrastructure becomes unavailable.
>
> **Known limitation:** Processing Infrastructure is the only service that validates crash events and triggers alerts. With it down, no alerts can fire regardless of what crash events are detected during the outage. All crash event data points, control message data points, and LWT messages accumulate in their respective SQS queues unread. All three queues are configured with a 14-day message retention period — independent of the Hot Storage 24-hour retention window. Hot Storage telemetry expires at 24 hours; SQS retains event data points for 14 days. On recovery, Processing Infrastructure drains all three queues: events from within 24 hours of the crash are processed via Branch A (full telemetry validation); events older than 24 hours are processed via Branch B (retrospective alert to rider — no Hot Storage data available). Events still unprocessed after 14 days expire from SQS with no cold storage record — a 14-day Processing Infrastructure outage is a catastrophic failure beyond the scope of this design. DLQ on each queue catches messages that fail to process after recovery (bug/error scenario during drain) and is not used for outage buffering.
>
> **Telemetry collection during outage:** The telemetry pipeline — Helmet → Smartphone → IoT Core → Telemetry Infrastructure → Hot Storage — has no dependency on Processing Infrastructure. Collection and Hot Storage writes continue normally throughout the outage. Crash event data points continue to be written to SQS Crash Queue by Telemetry Infrastructure on crash flag detection. LWT messages from IoT Core continue to be written to SQS LWT Queue. They simply accumulate unread.

---

### Monitoring Stack Detects Processing Infrastructure Failure
```
[Prometheus] → [Processing Infrastructure]         : /health endpoint scrape                                        : every 60 seconds
[Processing Infrastructure] → [Prometheus]         : no response                                                    : —
[Prometheus] → [Alertmanager]                      : alert fired, Processing Infrastructure unreachable, timestamp  : on health check failure threshold crossed
[Alertmanager] → [PagerDuty]                       : Processing Infrastructure down, timestamp                      : immediately
[PagerDuty] → [Infrastructure Engineer]            : page — Processing Infrastructure down, timestamp               : immediately via SMS and call
```

> See Flow 9A — Threshold Breach Detection for full monitoring chain.

---

### Rider Notification
```
[Monitoring Infrastructure] → [AWS IoT Core]       : publish infra down status, helmet ID, timestamp               : once per active helmet, on failure confirmed
[AWS IoT Core] → [Smartphone]                      : infra down status message                                      : via helmet/{helmet_id}/infra/status topic
[Smartphone App] → [Rider]                         : "Alert system failure — this is not a device issue, please ride with caution" : immediately
[Smartphone] → [Helmet HUD]                        : infra down status, helmet ID, timestamp                        : immediately via Bluetooth
[Helmet HUD] → [Rider]                             : "Alert system failure — this is not a device issue, please ride with caution" : immediately
```

---

### Device and Telemetry Behaviour During Outage
```
[Helmet Sensors] → [Helmet]               : accelerometer, speed, edge result, helmet ID, timestamp                 : every 1 second
[Helmet] → [Smartphone]                   : telemetry payload, helmet ID, timestamp                                 : every 1 second
[Smartphone] → [AWS IoT Core]             : telemetry payload, helmet ID, timestamp                                 : immediately via helmet/{helmet_id}/telemetry topic
[AWS IoT Core] → [Telemetry Infrastructure] : telemetry payload, helmet ID, timestamp                              : immediately via IoT Core rules engine
[Telemetry Infrastructure] → [Hot Storage] : batch payload, batch timestamp                                         : on every receive
[Telemetry Infrastructure] → [Telemetry Infrastructure] : inspect batch for crash flag                              : immediately
[Telemetry Infrastructure] → [SQS Crash Queue] : crash event data point, helmet ID, timestamp                         : if crash flag found — data point accumulates unread
```

> Telemetry collection and Hot Storage writes continue normally. SQS Crash Queue and SQS Control Queue accumulate unread data points. No alerts can fire during this period.

---

### Control Messages During Outage

> Low battery warnings and shutdown messages are forwarded by Telemetry Infrastructure to SQS Control Queue as normal. Processing Infrastructure cannot read them. No ack is sent back for shutdown messages.
```
[Telemetry Infrastructure] → [SQS Control Queue]  : control message data point, helmet ID, timestamp                  : on receiving low battery warning or shutdown message — data point accumulates unread
```

#### Shutdown During Outage — Helmet Behaviour
```
[Helmet] → [Helmet]                       : start acknowledgement timer on shutdown message sent                    : immediately after shutdown message forwarded to smartphone
[Helmet] → [Helmet]                       : no acknowledgement received within timer window                         : on timer expiry
[Helmet] → [Helmet]                       : power down, retain buffer storage                                       : on timer expiry
```

> Smartphone MQTT session remains active throughout — LWT does not fire. Cloud state for the helmet is ambiguous until Processing Infrastructure recovers and drains the SQS queues. No false alarm is triggered. Rider is already aware infra is down from the earlier status notification — no additional notification sent.

---

### DLQ Monitoring
```
[Prometheus] → [SQS Crash Queue]                   : queue depth, DLQ depth, message age                           : every 60 seconds
[Prometheus] → [SQS Control Queue]                 : queue depth, DLQ depth, message age                           : every 60 seconds
[Prometheus] → [SQS LWT Queue]                     : queue depth, DLQ depth, message age                           : every 60 seconds
[Prometheus] → [Alertmanager]                      : alert fired, DLQ depth non-zero, queue name, timestamp        : on DLQ messages detected
[Alertmanager] → [PagerDuty]                       : unprocessed messages in DLQ, queue name, message count, timestamp : immediately
[PagerDuty] → [Infrastructure Engineer]            : page — failed message processing detected in DLQ, investigate Processing Infrastructure : immediately via SMS and call
```

> DLQ messages indicate a processing failure (bug or error) that occurred during recovery drain — the message was received by Processing Infrastructure but failed to process after maxReceiveCount attempts. This is a different scenario from the outage itself, which is handled by the 14-day SQS retention period.

---

### On Processing Infrastructure Recovery
```
[Prometheus] → [Processing Infrastructure]         : /health endpoint scrape                                        : every 60 seconds
[Processing Infrastructure] → [Prometheus]         : health check passed                                            : on recovery
[Prometheus] → [Alertmanager]                      : alert resolved, Processing Infrastructure restored, timestamp  : immediately
[Alertmanager] → [PagerDuty]                       : Processing Infrastructure restored, timestamp                  : immediately
[PagerDuty] → [Infrastructure Engineer]            : Processing Infrastructure restored, timestamp                  : immediately
[Monitoring Infrastructure] → [AWS IoT Core]       : publish infra restored status, helmet ID, timestamp           : once per active helmet, on recovery confirmed
[AWS IoT Core] → [Smartphone]                      : infra restored status message                                  : via helmet/{helmet_id}/infra/status topic
[Smartphone App] → [Rider]                         : "Alert system restored — telemetry operational"               : immediately
[Smartphone] → [Helmet HUD]                        : infra restored status, helmet ID, timestamp                   : immediately via Bluetooth
[Helmet HUD] → [Rider]                             : "Alert system restored — telemetry operational"               : immediately
```

---

### Queue Drain on Recovery

#### Control Queue — Processed First
```
[Processing Infrastructure] → [SQS Control Queue] : read all held control message data points                     : immediately on recovery
[Processing Infrastructure] → [Processing Infrastructure] : process control messages in order per helmet ID         : immediately
[Processing Infrastructure] → [Processing Infrastructure] : apply state updates — mark helmet as low battery or offline as appropriate : on each message processed
```

> Control messages are state updates only. No cold storage writes, no alerts, no acks sent for already-timed-out helmets. Processed in order — any low battery warning for a helmet that also has a shutdown message is superseded immediately by the shutdown message with no harmful consequence.

---

#### LWT Queue — Processed Second
```
[Processing Infrastructure] → [SQS LWT Queue]    : read all held LWT messages                                   : after Control Queue drained
[Processing Infrastructure] → [Processing Infrastructure] : for each LWT — check if helmet already marked as gracefully offline from Control Queue drain : immediately
```

##### Sub-branch — Helmet Already Marked Gracefully Offline
```
[Processing Infrastructure] → [Processing Infrastructure] : discard LWT — graceful shutdown confirmed, LWT superseded : immediately
```

> No alert triggered. The LWT was fired by IoT Core before the graceful shutdown message was processed. Control Queue drain has already resolved the helmet state correctly.

##### Sub-branch — LWT Within 24 Hours of Occurrence (Hot Storage Data Available)
```
[Processing Infrastructure] → [Hot Storage]      : query last telemetry for helmet ID                            : immediately
[Hot Storage] → [Processing Infrastructure]      : last telemetry payload                                        : immediately
[Processing Infrastructure] → [Processing Infrastructure] : analyse last telemetry for crash flag, skip 5-second grace period — outage duration well exceeds it : immediately
```

> Proceeds as Flow 8 Case 1 (no crash flag — log unexpected dropout, no alert) or Case 2 (crash flag — validate and run retrospective alert mechanic). See Flow 8 for full branch detail.

##### Sub-branch — LWT Beyond 24 Hours of Occurrence (No Hot Storage Data Available)
```
[Processing Infrastructure] → [Hot Storage]      : query last telemetry for helmet ID                            : immediately
[Hot Storage] → [Processing Infrastructure]      : no data found — retention window expired                     : immediately
[Processing Infrastructure] → [SQS Alert Queue]         : cannot validate — alert type — retrospective, helmet ID, last known timestamp from LWT message : immediately
```

> Retrospective alert mechanic runs. Identical to Flow 4 Retrospective Alert. See Flow 4 — Retrospective Alert.
> Rider is presented with confirm or cancel. If rider is unreachable — cold storage log, no alert fired.

---

#### Crash Queue — Processed Last
```
[Processing Infrastructure] → [SQS Crash Queue]      : read all held crash event data points                         : after LWT Queue drained
[Processing Infrastructure] → [Hot Storage]           : query telemetry history for helmet ID                      : on each crash event data point read
```

---

#### Branch A — Within 24 Hours (Hot Storage Data Available)
```
[Hot Storage] → [Processing Infrastructure]           : recent telemetry history                                    : immediately
[Processing Infrastructure] → [Processing Infrastructure] : validate crash event against telemetry history          : immediately
```

##### Validated as False Positive
```
[Processing Infrastructure] → [Cold Storage]          : false positive log entry, helmet ID, crash timestamp, reason, processing delayed due to infra outage : immediately
```

> No alert fired.

##### Validated as Genuine Crash

```
[Processing Infrastructure] → [SQS Alert Queue]      : crash confirmed, alert type — retrospective, helmet ID, crash timestamp, incident location from crash data point : immediately
```

> Retrospective alert mechanic runs. Identical to Flow 4 Retrospective Alert. See Flow 4 — Retrospective Alert.

---

#### Branch B — Beyond 24 Hours (No Hot Storage Data Available)
```
[Hot Storage] → [Processing Infrastructure]           : no data found — retention window expired                    : immediately
[Processing Infrastructure] → [SQS Alert Queue]         : cannot validate — alert type — retrospective, helmet ID, crash timestamp, incident location from crash data point : immediately
```

> Retrospective alert mechanic runs. Identical to Flow 4 Retrospective Alert. See Flow 4 — Retrospective Alert. 

---

## Flow 9H — Alerting Infrastructure Failure

> **Precondition:** Telemetry Infrastructure, IoT Core, and Processing Infrastructure are all operational. Processing Infrastructure writes confirmed crash event data points to SQS Alert Queue. Alerting Infrastructure is down and cannot read the queue.
>
> **Known limitation:** No crash alerts can be dispatched to Next of Kin or Emergency Services during the outage. SQS Alert Queue is configured with a 14-day message retention period — all confirmed crash event data points accumulate unread and are drained on recovery. DLQ catches messages that fail to process after recovery (application-layer bug or error during drain) and is not used for outage buffering.

---

### Detection

```
[Prometheus] → [Alerting Infrastructure]           : /health endpoint scrape                                        : every 60 seconds
[Alerting Infrastructure] → [Prometheus]           : no response — health check failed                              : on scrape attempt during outage
[Prometheus] → [Alertmanager]                      : alert fired, Alerting Infrastructure unreachable, timestamp    : immediately
[Alertmanager] → [PagerDuty]                       : Alerting Infrastructure down, timestamp                        : immediately
[PagerDuty] → [Infrastructure Engineer]            : page — Alerting Infrastructure offline, investigate immediately : immediately via SMS and call
```

---

### Rider Notification

```
[Monitoring Infrastructure] → [AWS IoT Core]       : publish infra down status, helmet ID, timestamp               : once per active helmet, on failure confirmed
[AWS IoT Core] → [Smartphone]                      : infra down status message                                      : via helmet/{helmet_id}/infra/status topic
[Smartphone App] → [Rider]                         : "Alert system temporarily offline — emergency notifications paused" : immediately
[Smartphone] → [Helmet HUD]                        : infra down status, helmet ID, timestamp                        : immediately via Bluetooth
[Helmet HUD] → [Rider]                             : "Alert system temporarily offline — emergency notifications paused" : immediately
```

---

### Crash Confirmed During Outage

> Processing Infrastructure continues operating normally. Confirmed crash event data points are written to SQS Alert Queue as normal. Alerting Infrastructure is not reading the queue — data points accumulate unread. 14-day SQS retention ensures no event data point is lost during any realistic outage.

```
[Processing Infrastructure] → [SQS Alert Queue]   : crash confirmed, alert type — standard or retrospective, helmet ID, crash timestamp, incident location : on each validated genuine crash
```

> No alert is dispatched to Next of Kin or Emergency Services during the outage. Rider is already aware the alert system is offline — no additional per-crash notification sent.

---

### Mid-Countdown Failure

> If Alerting Infrastructure fails while a 30-second countdown is already in progress:

```
[Monitoring Infrastructure] → [AWS IoT Core]       : publish infra down status, helmet ID, timestamp               : on failure confirmed
[AWS IoT Core] → [Smartphone]                      : infra down status message                                      : via helmet/{helmet_id}/infra/status topic
[Smartphone App] → [Rider]                         : "Alert system offline — countdown cancelled, emergency services cannot be contacted" : immediately
[Smartphone] → [Helmet HUD]                        : infra down status, helmet ID, timestamp                        : immediately via Bluetooth
[Helmet HUD] → [Rider]                             : "Alert system offline — countdown cancelled, emergency services cannot be contacted" : immediately
```

> The in-progress crash event data point remains in SQS Alert Queue and is processed on recovery. Alert type determination runs at read time — see Flow 3 — Alerting Infrastructure Alert Type Determination.

---

### DLQ Monitoring

```
[Prometheus] → [SQS Alert Queue]                   : queue depth, DLQ depth, message age                            : every 60 seconds
[Prometheus] → [Alertmanager]                      : alert fired, DLQ depth non-zero, queue name, timestamp         : on DLQ messages detected
[Alertmanager] → [PagerDuty]                       : unprocessed messages in DLQ, queue name, message count, timestamp : immediately
[PagerDuty] → [Infrastructure Engineer]            : page — failed message processing detected in Alert Queue DLQ, investigate Alerting Infrastructure : immediately via SMS and call
```

> DLQ messages indicate an application-layer processing failure during recovery drain — the message was received by Alerting Infrastructure but failed to process after maxReceiveCount attempts. This is a different scenario from the outage itself, which is handled by the 14-day SQS retention period.

---

### On Alerting Infrastructure Recovery

```
[Prometheus] → [Alerting Infrastructure]           : /health endpoint scrape                                        : every 60 seconds
[Alerting Infrastructure] → [Prometheus]           : health check passed                                            : on recovery
[Prometheus] → [Alertmanager]                      : alert resolved, Alerting Infrastructure restored, timestamp    : immediately
[Alertmanager] → [PagerDuty]                       : Alerting Infrastructure restored, timestamp                    : immediately
[PagerDuty] → [Infrastructure Engineer]            : Alerting Infrastructure restored, timestamp                    : immediately
[Monitoring Infrastructure] → [AWS IoT Core]       : publish infra restored status, helmet ID, timestamp            : once per active helmet, on recovery confirmed
[AWS IoT Core] → [Smartphone]                      : infra restored status message                                   : via helmet/{helmet_id}/infra/status topic
[Smartphone App] → [Rider]                         : "Alert system restored — emergency notifications operational"  : immediately
[Smartphone] → [Helmet HUD]                        : infra restored status, helmet ID, timestamp                    : immediately via Bluetooth
[Helmet HUD] → [Rider]                             : "Alert system restored — emergency notifications operational"  : immediately
```

---

### Queue Drain on Recovery

```
[Alerting Infrastructure] → [SQS Alert Queue]      : read all held alert event data points                             : immediately on recovery, FCFS order
```

> Alert type determination runs on each event at read time. See Flow 3 — Alerting Infrastructure Alert Type Determination. Standard events are checked against the standard alert threshold in Parameter Store — events that have sat in the queue beyond the threshold are downgraded to retrospective. All retrospective events show a persistent confirm or cancel notification to the rider. If rider is unreachable — cold storage log, no alert fired.

---

## Flow 9I — Database Failure (Cloud Layer)

> **Precondition:** All other infrastructure components are operational. One or both database layers — Hot Storage or Cold Storage — become unavailable.
>
> **Two failure modes are covered in this flow:**
> 1. **Hot Storage failure** — telemetry writes fail, crash validation has no history to work against, all crash events are degraded to retrospective alert.
> 2. **Cold Storage failure** — audit trail writes fail, next of kin and emergency service contact lookups fail, alert dispatch is blocked.
>
> **Known limitation:** No database replication, standby replica, or multi-region failover is implemented in this project. A database failure is a service-degrading event with no automatic recovery path beyond restoring the primary instance. See Known Limitations at the end of this flow.

### Monitoring Stack Detects Database Failure

```
[Prometheus] → [Database — Hot Storage]            : /health endpoint scrape                                        : every 60 seconds
[Prometheus] → [Database — Cold Storage]           : /health endpoint scrape                                        : every 60 seconds
[Database] → [Prometheus]                          : no response                                                    : —
[Prometheus] → [Alertmanager]                      : alert fired, database unreachable, storage layer, timestamp    : on health check failure threshold crossed
[Alertmanager] → [PagerDuty]                       : database down, storage layer — hot or cold, timestamp          : immediately
[PagerDuty] → [Infrastructure Engineer]            : page — database failure, storage layer, timestamp              : immediately via SMS and call
```

> See Flow 9A — Threshold Breach Detection for full monitoring chain.

### Rider Notification

```
[Monitoring Infrastructure] → [AWS IoT Core]       : publish infra down status, helmet ID, timestamp               : once per active helmet, on failure confirmed
[AWS IoT Core] → [Smartphone]                      : infra down status message                                      : via helmet/{helmet_id}/infra/status topic
[Smartphone App] → [Rider]                         : "Alert system temporarily offline — emergency notifications paused" : immediately
[Smartphone] → [Helmet HUD]                        : infra down status, helmet ID, timestamp                        : immediately via Bluetooth
[Helmet HUD] → [Rider]                             : "Alert system temporarily offline — emergency notifications paused" : immediately
```

---

### Hot Storage Failure

#### Telemetry Behaviour During Outage

```
[Smartphone] → [AWS IoT Core]             : telemetry payload, helmet ID, timestamp                                 : every 10 seconds via helmet/{helmet_id}/telemetry topic
[AWS IoT Core] → [Telemetry Infrastructure] : telemetry payload                                                     : immediately via IoT Core rules engine
[Telemetry Infrastructure] → [Hot Storage] : batch payload, batch timestamp                                         : write fails — Hot Storage unavailable — batch dropped at write layer
```

> **Note:** Smartphone has no knowledge of Hot Storage failure and continues sending live telemetry normally. Telemetry Infra receives each batch but cannot write it — data is dropped at the write layer. No local buffering occurs on the smartphone side and no catch-up sync runs on recovery. Telemetry data sent during the outage is permanently lost.

#### Crash Event Handling During Hot Storage Outage

```
[Telemetry Infrastructure] → [Telemetry Infrastructure] : inspect batch for crash flag                              : immediately — independent of Hot Storage write result
[Telemetry Infrastructure] → [SQS Crash Queue] : crash event data point, helmet ID, timestamp                         : if crash flag found 
[Processing Infrastructure] → [SQS Crash Queue] : read crash event data point                                         : event-driven
[Processing Infrastructure] → [Hot Storage]    : query telemetry history for helmet ID                               : immediately
[Hot Storage] → [Processing Infrastructure]    : no data found — storage unavailable                                 : immediately
[Processing Infrastructure] → [SQS Alert Queue] : cannot validate — alert type — retrospective, helmet ID, crash timestamp, incident location from crash data point : immediately
```

> All crash events during a Hot Storage outage are degraded to retrospective regardless of how soon they are processed. Rider is presented with confirm or cancel on both devices. See Flow 4 — Retrospective Alert.

#### On Hot Storage Recovery

```
[Prometheus] → [Database — Hot Storage]            : /health endpoint scrape                                        : every 60 seconds
[Database — Hot Storage] → [Prometheus]            : health check passed                                            : on recovery
[Prometheus] → [Alertmanager]                      : alert resolved, Hot Storage restored, timestamp                : immediately
[Alertmanager] → [PagerDuty]                       : Hot Storage restored, timestamp                                : immediately
[PagerDuty] → [Infrastructure Engineer]            : Hot Storage restored, timestamp                                : immediately
[Monitoring Infrastructure] → [AWS IoT Core]       : publish infra restored status, helmet ID, timestamp            : once per active helmet, on recovery confirmed
[AWS IoT Core] → [Smartphone]                      : infra restored status message                                   : via helmet/{helmet_id}/infra/status topic
[Smartphone App] → [Rider]                         : "Alert system restored — emergency notifications operational"  : immediately
[Smartphone] → [Helmet HUD]                        : infra restored status, helmet ID, timestamp                    : immediately via Bluetooth
[Helmet HUD] → [Rider]                             : "Alert system restored — emergency notifications operational"  : immediately
```

> Normal writes resume for new batches; no catch-up runs for data dropped during the outage. SQS Crash Queue data points held during the outage are processed on recovery — events that find no corresponding history in Hot Storage (either because it was dropped during the outage or expired via TTL) are degraded to retrospective as normal.

---

### Cold Storage Failure

#### Alert Dispatch Behaviour During Outage

> Alerting Infrastructure looks up next of kin and emergency service contact details from Cold Storage at alert dispatch time. If Cold Storage is unavailable, that lookup fails and the alert cannot be sent.

```
[Alerting Infrastructure] → [SQS Alert Queue]      : read alert event data point                                     : event-driven
[Alerting Infrastructure] → [Cold Storage]         : look up next of kin contact details, helmet ID                 : immediately on read
[Cold Storage] → [Alerting Infrastructure]         : no response — Cold Storage unavailable                          : —
[Alerting Infrastructure] → [Alerting Infrastructure] : contact lookup failed — alert cannot be dispatched, retain event in queue : immediately
```

> SQS Alert Queue 14-day retention holds all undelivered events. On Cold Storage recovery, Alerting Infrastructure drains the queue and dispatches.

#### Audit Trail Write Failures During Outage

> All cold storage writes — incident records, false positive logs, cancellation records, delivery logs — fail during the outage.

```
[Alerting Infrastructure] → [Cold Storage]         : incident record write — fails, Cold Storage unavailable          : on each resolution attempt during outage
```

> **Note:** This is a permanent audit trail gap for the duration of the outage. There is no replay mechanism for cold storage writes in this design.

#### On Cold Storage Recovery

```
[Prometheus] → [Database — Cold Storage]           : /health endpoint scrape                                        : every 60 seconds
[Database — Cold Storage] → [Prometheus]            : health check passed                                            : on recovery
[Prometheus] → [Alertmanager]                      : alert resolved, Cold Storage restored, timestamp               : immediately
[Alertmanager] → [PagerDuty]                       : Cold Storage restored, timestamp                               : immediately
[PagerDuty] → [Infrastructure Engineer]            : Cold Storage restored, timestamp                               : immediately
[Monitoring Infrastructure] → [AWS IoT Core]       : publish infra restored status, helmet ID, timestamp            : once per active helmet, on recovery confirmed
[AWS IoT Core] → [Smartphone]                      : infra restored status message                                   : via helmet/{helmet_id}/infra/status topic
[Smartphone App] → [Rider]                         : "Alert system restored — emergency notifications operational"  : immediately
[Smartphone] → [Helmet HUD]                        : infra restored status, helmet ID, timestamp                    : immediately via Bluetooth
[Helmet HUD] → [Rider]                             : "Alert system restored — emergency notifications operational"  : immediately
```

> SQS Alert Queue drains on recovery. Contact lookups succeed. Alert dispatch resumes. Audit trail writes resume for all new events — events that failed to write during the outage are not recovered.

---

### Known Limitations

#### No replication or standby replica
Both Hot Storage and Cold Storage run as single instances in this project. A database failure has no automatic failover path. Recovery depends on the engineer restoring the primary instance. For a production deployment, a read replica or standby instance would allow automatic promotion on failure, reducing downtime from minutes to seconds.

#### Audit trail gap on Cold Storage failure
Cold storage writes that fail during an outage are permanently lost. There is no write-ahead log or replay buffer on the application side. In a production deployment, a durable write-ahead log (e.g. writing to an SQS queue first and draining to cold storage) would eliminate this gap.

#### Telemetry data loss during Hot Storage failure
Because the smartphone sends live telemetry fire-and-forget with no per-batch ack, it has no knowledge of Hot Storage write failures. Data sent during the outage is dropped at the write layer with no recovery path. Unlike Telemetry Infrastructure failure — where the smartphone cannot reach the service and therefore buffers locally — Hot Storage failure is invisible to the device layer. This is a known, accepted limitation for a portfolio project. A production deployment could mitigate this by having Telemetry Infrastructure buffer failed writes internally with a retry queue.

#### All crash events degraded to retrospective during Hot Storage failure
The retrospective alert mechanic depends on rider availability. If the rider is unreachable, no alert fires. A production deployment could mitigate this with a caching layer (e.g. ElastiCache) that holds a short window of recent telemetry in memory, allowing Branch A validation even during a brief Hot Storage outage.

#### Multi-region redundancy out of scope
No multi-region or cross-AZ database strategy is implemented. A regional outage affecting the database would take the alert system down entirely. This is a known, accepted limitation for a portfolio project.

#### Smartphone Buffer Exhaustion
The local storage capacity of the smartphone is finite. If a cloud-side outage (e.g., Telemetry Infrastructure failure) lasts long enough, the smartphone will eventually run out of space to store new telemetry chunks. Currently, the behavior for a full buffer is not explicitly enforced at the protocol level, which could lead to application-layer crashes or data stalls on the device.

---

## Future Enhancements (Post-MVP)

#### Circular Buffer Implementation for Device Layer
To handle extreme outages, the Smartphone App and Helmet firmware can implement a circular buffer strategy. Once the local storage limit is reached, newest data would overwrite the oldest payloads. This ensures the system remains "live" for the most recent events, prioritizing current safety detection over historical logs.

#### Fleet-wide Buffer Monitoring
Implement cloud-side monitoring of "Average Buffer Depth" across the fleet. If a statistically significant percentage of helmets report a high buffer percentage (via a periodic heartbeat), the DevOps monitoring stack should trigger a Critical Alert, identifying a systemic infrastructure bottleneck or regional outage before devices hit their storage limits.

#### Write-Ahead Logging (WAL) for Cold Storage
To eliminate the audit trail gap during Cold Storage failures, implement a durable write-ahead log. All logs would be written to a dedicated SQS "Log Queue" first, with a consumer service responsible for draining them into Cold Storage once the database is healthy.


### Flow 9J — Parameter Store Unavailability (Config Layer)

#### Parameter Store Cache Miss (During Refresh Cycle)

```
[Processing Infrastructure] → [AWS Parameter Store]      : fetch mass alert threshold, crash confirmation threshold        : every 5 minutes (cache refresh)
[AWS Parameter Store] → [Processing Infrastructure]      : no response — Parameter Store unavailable                       : —
[Processing Infrastructure] → [Processing Infrastructure] : cache refresh failed — retain last known values, continue operating : immediately
```

```
[Alerting Infrastructure] → [AWS Parameter Store]        : fetch standard alert threshold                                  : every 5 minutes (cache refresh)
[AWS Parameter Store] → [Alerting Infrastructure]        : no response — Parameter Store unavailable                       : —
[Alerting Infrastructure] → [Alerting Infrastructure]    : cache refresh failed — retain last known values, continue operating : immediately
```

```
[Telemetry Infrastructure] → [AWS Parameter Store]       : fetch TTL value                                                 : every 5 minutes (cache refresh)
[AWS Parameter Store] → [Telemetry Infrastructure]       : no response — Parameter Store unavailable                       : —
[Telemetry Infrastructure] → [Telemetry Infrastructure]  : cache refresh failed — retain last known values, continue operating : immediately
```

#### Service Restart During Outage (Cold Start Fallback)

```
[Processing Infrastructure] → [AWS Parameter Store]      : fetch mass alert threshold, crash confirmation threshold        : on service restart during outage
[AWS Parameter Store] → [Processing Infrastructure]      : no response — Parameter Store unavailable                       : —
[Processing Infrastructure] → [Processing Infrastructure] : SSM fetch failed — load hardcoded default values, continue operating : immediately
```

> Same cold start fallback applies to Alerting Infrastructure and Telemetry Infrastructure independently. Each service loads its own hardcoded defaults and continues operating. No service blocks on Parameter Store availability.

#### Monitoring and Engineer Alert

```
[Prometheus] → [AWS Parameter Store]                     : /health endpoint scrape                                         : every 60 seconds
[AWS Parameter Store] → [Prometheus]                     : no response — Parameter Store unavailable                       : —
[Prometheus] → [Alertmanager]                            : Parameter Store unavailable, timestamp                          : immediately
[Alertmanager] → [PagerDuty]                             : Parameter Store unavailable, timestamp                          : immediately
[PagerDuty] → [Infrastructure Engineer]                  : Parameter Store unavailable, timestamp                          : immediately
```

#### Rider Notification

```
[Monitoring Infrastructure] → [AWS IoT Core]             : publish degraded status, helmet ID, timestamp                   : once per active helmet, on outage confirmed
[AWS IoT Core] → [Smartphone]                            : degraded status message                                         : via helmet/{helmet_id}/infra/status topic
[Smartphone App] → [Rider]                               : "Systems operational — caution advised while riding"            : immediately
[Smartphone] → [Helmet HUD]                              : degraded status, helmet ID, timestamp                           : immediately via Bluetooth
[Helmet HUD] → [Rider]                                   : "Systems operational — caution advised while riding"            : immediately
```

#### On Parameter Store Recovery

```
[Prometheus] → [AWS Parameter Store]                     : /health endpoint scrape                                         : every 60 seconds
[AWS Parameter Store] → [Prometheus]                     : health check passed                                             : on recovery
[Prometheus] → [Alertmanager]                            : alert resolved, Parameter Store restored, timestamp             : immediately
[Alertmanager] → [PagerDuty]                             : Parameter Store restored, timestamp                             : immediately
[PagerDuty] → [Infrastructure Engineer]                  : Parameter Store restored, timestamp                             : immediately
[Processing Infrastructure] → [AWS Parameter Store]      : fetch mass alert threshold, crash confirmation threshold        : on next 5-minute cache refresh
[Alerting Infrastructure] → [AWS Parameter Store]        : fetch standard alert threshold                                  : on next 5-minute cache refresh
[Telemetry Infrastructure] → [AWS Parameter Store]       : fetch TTL value                                                 : on next 5-minute cache refresh
[Monitoring Infrastructure] → [AWS IoT Core]             : publish systems restored status, helmet ID, timestamp           : once per active helmet, on recovery confirmed
[AWS IoT Core] → [Smartphone]                            : systems restored status message                                 : via helmet/{helmet_id}/infra/status topic
[Smartphone App] → [Rider]                               : "Systems fully operational"                                     : immediately
[Smartphone] → [Helmet HUD]                              : systems restored status, helmet ID, timestamp                   : immediately via Bluetooth
[Helmet HUD] → [Rider]                                   : "Systems fully operational"                                     : immediately
```

> All services resume reading live Parameter Store values on their next cache refresh cycle. No manual intervention or redeployment required. Services that were running on hardcoded defaults during a cold start will also pick up live values on their next refresh — the hardcoded defaults are a one-time fallback, not a permanent override.

---

## Flow 9K — Bad Firmware Update (Config Layer)

> **Precondition:** Fleet Manager is rolling out a new firmware version using AWS IoT Device Management. A canary rollout strategy is used — a defined percentage of the fleet receives the new firmware first. The remaining devices are held on the current stable version until the canary group passes a defined observation window.
>
> **Delivery path:** AWS IoT Device Management delivers firmware jobs to devices through AWS IoT Core → Smartphone → Helmet via Bluetooth. Helmet NEVER communicates directly with cloud — all install status reports travel back through Smartphone → IoT Core → Device Management.
>
> **Install timing (staged model):** The firmware package is delivered OTA and staged locally on the helmet — it does NOT install during the current session. The update applies on the next helmet power cycle. This is consistent with the delivery mechanics defined in Flow 10.

> **New MQTT topics introduced:**
> - `helmet/{helmet_id}/firmware/update` — cloud-to-device firmware update packages, published by AWS IoT Device Management through IoT Core, subscribed by Smartphone, relayed to Helmet via Bluetooth.
> - `helmet/{helmet_id}/firmware/status` — device-to-cloud install status reports, published by Smartphone on behalf of Helmet, routed to AWS IoT Device Management via IoT Core rules engine.
> - Both topics provisioned in Terraform alongside all other MQTT topics.

> **Firmware version field:** Embedded in every telemetry payload — the primary correlation mechanism for detecting anomalies tied to a specific firmware version. See Telemetry Batching Design in Project Context.
>
> **Two failure branches:** Branch A covers installation failure — the staged firmware fails to apply on power cycle. Branch B covers post-install behavioural anomaly — the update installs successfully but the firmware behaves incorrectly in the field, detected via abnormal crash flag rates correlated to the canary firmware version.
>
> **Response (both branches):** Halt the rollout to the remaining fleet, automatically roll back the canary group to the previous stable firmware version, and page the Fleet Manager. A device on a bad or partially installed firmware is more dangerous than a device on the previous stable release — restoring a known working state takes priority.
>
> **Firmware anomaly threshold:** Stored in Parameter Store. Processing Infrastructure watches the metric and triggers the halt — it does not need to understand why the anomaly occurred. Investigation is handled offline after the fleet is restored.
>
> **Cross-reference:** Flow 10 defines the full operational firmware rollout lifecycle — job creation, canary delivery, observation window, full fleet rollout, abort criteria, and rollback mechanics. Flow 9K focuses specifically on the two failure modes (installation failure and behavioural anomaly) and their detection and response paths.

---

### Canary Rollout Initiation

```
[Fleet Manager] → [AWS IoT Device Management]          : initiate firmware rollout job, firmware version, observation window, canary percentage : on new firmware release
[AWS IoT Device Management] → [Cold Storage]            : query canary group device IDs, current firmware version                : immediately
[Cold Storage] → [AWS IoT Device Management]            : canary group device IDs, current firmware version                     : immediately
[AWS IoT Device Management] → [AWS IoT Core]            : firmware update job, canary group device IDs, firmware package        : immediately
[AWS IoT Core] → [Smartphone]                           : firmware update package, version identifier, helmet ID               : via helmet/{helmet_id}/firmware/update topic
[Smartphone] → [Helmet — Canary Group]                  : firmware update package, version identifier                          : immediately via Bluetooth
[Helmet — Canary Group] → [Helmet — Canary Group]       : stage firmware package locally — do not install                      : on package received
[Helmet — Canary Group] → [Smartphone]                  : package staged acknowledgement, device ID, firmware version, timestamp : immediately
[Smartphone] → [AWS IoT Core]                           : package staged acknowledgement, device ID, firmware version, timestamp : immediately via helmet/{helmet_id}/firmware/status topic
[AWS IoT Core] → [AWS IoT Device Management]            : package staged acknowledgement, device ID, firmware version, timestamp : immediately via rules engine
[Helmet — Canary Group] → [Helmet — Canary Group]       : apply staged firmware on startup                                     : on next power cycle
[Helmet — Canary Group] → [Smartphone]                  : install status report — success or failure, device ID, firmware version, timestamp : on install attempt complete
[Smartphone] → [AWS IoT Core]                           : install status report, device ID, firmware version, timestamp        : immediately via helmet/{helmet_id}/firmware/status topic
[AWS IoT Core] → [AWS IoT Device Management]            : install status report — success or failure, device ID, firmware version, timestamp : immediately via rules engine
```

> Fleet Manager owns the firmware pipeline and rollout strategy. Infrastructure Engineer is notified of failures but does not initiate or control firmware rollouts.

---

### Happy Path — Observation Window Passes

```
[AWS IoT Device Management] → [AWS IoT Device Management] : all canary group installs successful, start observation window timer : on all install success reports received
[AWS IoT Device Management] → [AWS IoT Device Management] : observation window passed, no anomalies detected                   : on timer expiry with no halt signal received from Processing Infrastructure
[AWS IoT Device Management] → [AWS IoT Core]            : firmware update job, remaining fleet device IDs, firmware package    : immediately
[AWS IoT Core] → [Smartphone]                           : firmware update package, version identifier, helmet ID               : via helmet/{helmet_id}/firmware/update topic
[Smartphone] → [Helmet — Remaining Fleet]               : firmware update package, version identifier                          : immediately via Bluetooth
[Helmet — Remaining Fleet] → [Helmet — Remaining Fleet] : stage firmware package locally — do not install                      : on package received
[Helmet — Remaining Fleet] → [Smartphone]               : package staged acknowledgement, device ID, firmware version, timestamp : immediately
[Smartphone] → [AWS IoT Core]                           : package staged acknowledgement, device ID, firmware version, timestamp : immediately via helmet/{helmet_id}/firmware/status topic
[AWS IoT Core] → [AWS IoT Device Management]            : package staged acknowledgement, device ID, firmware version, timestamp : immediately via rules engine
[Helmet — Remaining Fleet] → [Helmet — Remaining Fleet] : apply staged firmware on startup                                     : on next power cycle per device
[Helmet — Remaining Fleet] → [Smartphone]               : install status report — success, device ID, firmware version, timestamp : on install complete
[Smartphone] → [AWS IoT Core]                           : install status report, device ID, firmware version, timestamp        : immediately via helmet/{helmet_id}/firmware/status topic
[AWS IoT Core] → [AWS IoT Device Management]            : install status report — success, device ID, firmware version, timestamp : immediately via rules engine
[AWS IoT Device Management] → [Cold Storage]            : firmware rollout record, firmware version, rollout completed, all devices updated, timestamp : on all install success reports received
```

> Full fleet on new firmware. No further automated action. Observation continues via normal telemetry pipeline.

---

### Branch A — Installation Failure

> Installation failure is now detected at power cycle time, not at delivery time. The helmet stages the package successfully but fails to apply it on restart. The install status report carries a failure flag.

```
[AWS IoT Device Management] → [AWS IoT Device Management] : failure count against canary group size — threshold breached        : on install failure reports received
[AWS IoT Device Management] → [AWS IoT Device Management] : halt rollout to remaining fleet                                     : immediately on threshold breach
[AWS IoT Device Management] → [AWS IoT Core]            : rollback job, failed canary device IDs, previous stable firmware version : immediately
[AWS IoT Core] → [Smartphone]                           : rollback package, previous stable firmware version, helmet ID        : via helmet/{helmet_id}/firmware/update topic
[Smartphone] → [Helmet — Canary Group]                  : rollback package, previous stable firmware version                   : immediately via Bluetooth
[Helmet — Canary Group] → [Helmet — Canary Group]       : stage rollback package locally — do not install                      : on package received
[Helmet — Canary Group] → [Smartphone]                  : package staged acknowledgement, device ID, previous stable firmware version, timestamp : immediately
[Smartphone] → [AWS IoT Core]                           : package staged acknowledgement, device ID, previous stable firmware version, timestamp : immediately via helmet/{helmet_id}/firmware/status topic
[AWS IoT Core] → [AWS IoT Device Management]            : package staged acknowledgement, device ID, previous stable firmware version, timestamp : immediately via rules engine
[Helmet — Canary Group] → [Helmet — Canary Group]       : apply staged rollback firmware on startup                            : on next power cycle
[Helmet — Canary Group] → [Smartphone]                  : rollback install status — success, device ID, firmware version, timestamp : on rollback install complete
[Smartphone] → [AWS IoT Core]                           : rollback install status, device ID, firmware version, timestamp      : immediately via helmet/{helmet_id}/firmware/status topic
[AWS IoT Core] → [AWS IoT Device Management]            : rollback install status — success, device ID, firmware version, timestamp : immediately via rules engine
```

#### Monitoring and Alerting — Installation Failure

```
[CloudWatch] → [CloudWatch]                             : firmware rollout failure metric, firmware version, failure count, timestamp : on rollout halted
[CloudWatch] → [SNS]                                    : firmware rollout failure alarm, firmware version, failure count, timestamp : immediately on alarm threshold
[SNS] → [PagerDuty]                                     : firmware rollout failure, firmware version, failure count, timestamp  : immediately
[PagerDuty] → [Fleet Manager]                           : page — firmware rollout failure, firmware version, failure count, timestamp : immediately via SMS and call
[PagerDuty] → [Infrastructure Engineer]                 : page — firmware rollout failure, firmware version, failure count, timestamp : immediately via SMS and call
```

> Devices that never received the update remain on the current stable firmware and are unaffected. Devices in the canary group that failed installation are rolled back to the previous stable version. Fleet returns to a fully known stable state.
>
> AWS IoT Device Management is an AWS-managed service — its metrics are surfaced via CloudWatch and routed through SNS, consistent with how IoT Core and database metrics are handled in the monitoring stack (see Flow 9A).

---

### Branch B — Post-Install Behavioural Anomaly

> Detection runs through the existing telemetry pipeline. Telemetry data flows normally — Helmet → Smartphone → IoT Core → Telemetry Infrastructure → Hot Storage. Crash flags detected by Telemetry Infrastructure are written to SQS Crash Queue as normal. Processing Infrastructure reads from SQS Crash Queue and correlates crash flag rates against the canary firmware version using the firmware anomaly threshold from Parameter Store.
>
> Cross-reference: Mass Alert Decision Logic Step 2 (firmware version correlation check) uses the same firmware version field for fleet-wide anomaly detection. Flow 9K operates specifically within the canary rollout lifecycle.

#### Anomaly Detection

```
[Helmet — Canary Group Sensors] → [Helmet — Canary Group] : accelerometer, speed, edge result, firmware version, helmet ID, timestamp : every 1 second
[Helmet — Canary Group] → [Smartphone]                  : telemetry payload, crash flag, firmware version, helmet ID, timestamp : every 1 second
[Smartphone] → [AWS IoT Core]                           : JSON array of 10 telemetry payloads + GPS + user ID + batch timestamp : every 10 seconds via helmet/{helmet_id}/telemetry topic
[AWS IoT Core] → [Telemetry Infrastructure]             : telemetry batch, helmet ID                                          : immediately via IoT Core rules engine
[Telemetry Infrastructure] → [Hot Storage]              : batch payload, batch timestamp                                       : on every receive
[Telemetry Infrastructure] → [Telemetry Infrastructure] : inspect batch for crash flag                                        : immediately
[Telemetry Infrastructure] → [SQS Crash Queue]          : crash event data point, firmware version, helmet ID, timestamp       : if crash flag found
[Processing Infrastructure] → [SQS Crash Queue]         : read crash event data point                                          : event-driven
[Processing Infrastructure] → [Processing Infrastructure] : correlate crash flag rate against canary firmware version — check against firmware anomaly threshold from Parameter Store cache : immediately
[Processing Infrastructure] → [Processing Infrastructure] : firmware anomaly threshold breached                                : on breach detected
```

#### Halt and Rollback

```
[Processing Infrastructure] → [AWS IoT Device Management] : halt rollout signal, firmware version, anomaly rate, timestamp    : immediately on threshold breach
[AWS IoT Device Management] → [AWS IoT Device Management] : halt rollout to remaining fleet                                    : immediately
[AWS IoT Device Management] → [AWS IoT Core]            : rollback job, canary group device IDs, previous stable firmware version : immediately
[AWS IoT Core] → [Smartphone]                           : rollback package, previous stable firmware version, helmet ID        : via helmet/{helmet_id}/firmware/update topic
[Smartphone] → [Helmet — Canary Group]                  : rollback package, previous stable firmware version                   : immediately via Bluetooth
[Helmet — Canary Group] → [Helmet — Canary Group]       : stage rollback package locally — do not install                      : on package received
[Helmet — Canary Group] → [Smartphone]                  : package staged acknowledgement, device ID, previous stable firmware version, timestamp : immediately
[Smartphone] → [AWS IoT Core]                           : package staged acknowledgement, device ID, previous stable firmware version, timestamp : immediately via helmet/{helmet_id}/firmware/status topic
[AWS IoT Core] → [AWS IoT Device Management]            : package staged acknowledgement, device ID, previous stable firmware version, timestamp : immediately via rules engine
[Helmet — Canary Group] → [Helmet — Canary Group]       : apply staged rollback firmware on startup                            : on next power cycle
[Helmet — Canary Group] → [Smartphone]                  : rollback install status — success, device ID, firmware version, timestamp : on rollback install complete
[Smartphone] → [AWS IoT Core]                           : rollback install status, device ID, firmware version, timestamp      : immediately via helmet/{helmet_id}/firmware/status topic
[AWS IoT Core] → [AWS IoT Device Management]            : rollback install status — success, device ID, firmware version, timestamp : immediately via rules engine
```

#### Monitoring and Alerting — Behavioural Anomaly

```
[CloudWatch] → [CloudWatch]                             : firmware anomaly metric, firmware version, anomaly rate, timestamp   : on anomaly detected
[CloudWatch] → [SNS]                                    : firmware anomaly alarm, firmware version, anomaly rate, timestamp    : immediately on alarm threshold
[SNS] → [PagerDuty]                                     : firmware anomaly detected, firmware version, anomaly rate, timestamp : immediately
[PagerDuty] → [Fleet Manager]                           : page — firmware anomaly detected, firmware version, anomaly rate, timestamp : immediately via SMS and call
[PagerDuty] → [Infrastructure Engineer]                 : page — firmware anomaly detected, firmware version, anomaly rate, timestamp : immediately via SMS and call
```

> Canary group devices that installed the new firmware successfully are rolled back to the previous stable version regardless — a known bad firmware release is pulled from the entire canary group, not selectively from failing devices. Devices that never received the update are unaffected. Fleet returns to a fully known stable state.

---

### Rider Notification (Both Branches)

```
[Monitoring Infrastructure] → [AWS IoT Core]            : publish degraded status, helmet ID, timestamp                       : once per affected helmet, on rollback initiated
[AWS IoT Core] → [Smartphone]                           : degraded status message                                              : via helmet/{helmet_id}/infra/status topic
[Smartphone App] → [Rider]                              : "Systems operational — caution advised while riding"                : immediately
[Smartphone] → [Helmet HUD]                             : degraded status, helmet ID, timestamp                                : immediately via Bluetooth
[Helmet HUD] → [Rider]                                  : "Systems operational — caution advised while riding"                : immediately
```

> Rider is not informed of the firmware rollback specifically — the degraded status message is intentionally generic. Same message as Parameter Store unavailability (Flow 9J).

---

### On Rollback Complete (Both Branches)

```
[AWS IoT Device Management] → [Cold Storage]            : firmware rollback record, firmware version, rollback reason — install failure or behavioural anomaly, devices affected, timestamp : on all rollback confirmations received
[CloudWatch] → [CloudWatch]                             : rollback complete metric, all canary group devices on stable firmware, timestamp : on all rollback confirmations received
[CloudWatch] → [SNS]                                    : rollback complete alarm resolved, timestamp                          : immediately
[SNS] → [PagerDuty]                                     : rollback complete, timestamp                                        : immediately
[PagerDuty] → [Fleet Manager]                           : rollback complete, all canary devices on stable firmware, timestamp  : immediately
[PagerDuty] → [Infrastructure Engineer]                 : rollback complete, timestamp                                        : immediately
[Monitoring Infrastructure] → [AWS IoT Core]            : publish systems restored status, helmet ID, timestamp                : once per affected helmet, on rollback confirmed
[AWS IoT Core] → [Smartphone]                           : systems restored status message                                      : via helmet/{helmet_id}/infra/status topic
[Smartphone App] → [Rider]                              : "Systems fully operational"                                         : immediately
[Smartphone] → [Helmet HUD]                             : systems restored status, helmet ID, timestamp                        : immediately via Bluetooth
[Helmet HUD] → [Rider]                                  : "Systems fully operational"                                         : immediately
```

> No further automated action is taken. Re-release of a fixed firmware version is a separate, manually initiated process by the Fleet Manager. The failed firmware version is not retried automatically.

---

### Known Limitations

#### No post-rollback health verification window
The system confirms rollback installation success via device status reports but does not run a dedicated observation window to verify that rolled-back devices are behaving correctly before publishing the restored status to riders. A corrupt or incomplete rollback package could leave devices in an unknown state that is not caught until the next telemetry anomaly detection cycle.

#### Firmware anomaly threshold cannot disambiguate a genuine mass incident
The firmware anomaly threshold detects abnormal crash flag rates correlated to a canary firmware version. If a genuine mass incident coincidentally occurs during a canary rollout window, the same signal could trigger an erroneous rollback. Disambiguating the two scenarios is an offline investigation task — the system always prioritises rolling back over waiting for confirmation.

#### Rollback depends on IoT Core and Smartphone availability
The rollback delivery path runs through IoT Core → Smartphone → Helmet. If IoT Core is degraded during a firmware rollout failure, or if a rider's Smartphone is offline, the rollback package cannot be delivered to that device. Devices remain on the failed firmware until both IoT Core and Smartphone connectivity are restored. This is a known, accepted limitation for a portfolio project.

#### Observation window anomaly detection relies on normal telemetry pipeline
Behavioural anomaly detection (Branch B) requires the full telemetry pipeline to be operational — Telemetry Infrastructure must be writing crash data points to SQS Crash Queue, and Processing Infrastructure must be reading them. If either service is down during the canary observation window, anomalies may not be detected until the services recover, by which time the observation window may have passed and full fleet rollout may have been triggered.

---

## Flow 9L — Bad Infrastructure Deploy (CI/CD Pipeline)

> **Precondition:** The Infrastructure Engineer is rolling out an update via the CI/CD pipeline (e.g., GitHub Actions). The update involves both Infrastructure Code (Terraform) and Application Code (ECS Docker Image).
>
> **Monorepo setup:** The repository places Infrastructure Code (`/infrastructure`) and Application Code (`/application`) in separate directories. Path filtering in CI/CD ensures that changes to one don't unnecessarily trigger builds in the other.
>
> **Three failure stages are defined:**
> - **Stage 1 (Pre-Deploy):** Caught by the CI/CD pipeline before any AWS resources are touched.
> - **Stage 2 (Deploy-Time):** Terraform apply fails halfway through.
> - **Stage 3 (Post-Deploy Application Failure):** Terraform succeeds, but the new Application container has a bad configuration and fails to start natively within AWS.
>
> **Safety mechanisms used:**
> - **Terraform Validation:** `terraform validate` and `terraform plan` run in CI/CD.
> - **Rolling Updates:** Used for ECS Fargate Application deployments. ECS does not kill the old stable task until the new task passes its `/health` check.

---

### Stage 1 — Pre-Deploy Failure (The Gatekeeper)

> Developer pushes a commit with a syntax error in Terraform (e.g., missing bracket or invalid parameter).

```
[Infrastructure Engineer] → [GitHub Repo]                      : git push with syntax error                                : on local commit
[GitHub Actions CI/CD] → [GitHub Repo]                         : checkout code                                             : on push trigger
[GitHub Actions CI/CD] → [Terraform]                           : run `terraform validate`                                  : immediately
[Terraform] → [GitHub Actions CI/CD]                           : syntax error, exit code 1                                 : immediately
[GitHub Actions CI/CD] → [Infrastructure Engineer]             : pipeline failed notification, build log                   : immediately via Slack/Email
```

> **Result:** No AWS resources are touched. The "Stable Infra" in AWS remains unmodified. The Engineer fixes the syntax locally and pushes a new commit.

---

### Stage 2 — Deploy-Time Failure (The Lockout)

> Developer pushes structurally valid Terraform code, but it fails during `terraform apply` (e.g., AWS service quota reached, or IAM permission denied).

```
[Infrastructure Engineer] → [GitHub Repo]                      : git push with valid syntax but invalid permissions        : on local commit
[GitHub Actions CI/CD] → [Terraform]                           : run `terraform validate` + `terraform plan`               : completes successfully
[GitHub Actions CI/CD] → [Terraform]                           : run `terraform apply`                                     : begins modifying AWS resources
[AWS IAM / Service Quota] → [Terraform]                        : permission denied / quota exceeded error                  : during resource creation
[Terraform] → [S3 / DynamoDB]                                  : write partial state file, release lock                    : immediately
[Terraform] → [GitHub Actions CI/CD]                           : apply failed, exit code 1                                 : immediately
[GitHub Actions CI/CD] → [Infrastructure Engineer]             : pipeline failed notification, build log                   : immediately via Slack/Email
```

> **Result:** The infrastructure is in a "half-baked" state (e.g., SQS Queue was created, but IoT Rule was denied).
> 
> **Recovery:** The Infrastructure Engineer uses `git revert <bad_commit>` to restore the repository to the previously known "Stable" state. The CI/CD pipeline automatically runs `terraform apply` on this reverted commit, which destroys the half-baked resources and returns the AWS environment to its stable baseline.

---

### Stage 3 — Post-Deploy Application Failure (The Silent Killer Caught by ECS)

> The Infrastructure code deploys successfully. A new Application container (e.g., Telemetry Infrastructure) is deployed to ECS, but it contains a bad configuration (e.g., it listens on the wrong port, or crashes immediately on startup).
> 
> **CRITICAL:** Data loss is prevented here primarily by ECS's native **Rolling Update** deployment strategy combined with configured `/health` checks.

```
[GitHub Actions CI/CD] → [AWS ECS]                             : deploy new `Telemetry Infrastructure` task definition (v2) : on successful pipeline
[AWS ECS] → [AWS ECS]                                          : start 1 new task (v2)                                     : deployment minimum healthy percent = 100%
[AWS ECS] → [Telemetry Infrastructure v2]                      : ping `/health` endpoint                                   : according to configured interval
[Telemetry Infrastructure v2] → [AWS ECS]                      : connection refused or process crashed                     : on health check
[AWS ECS] → [AWS ECS]                                          : mark v2 task as UNHEALTHY                                 : after max timeout/retries
[AWS ECS] → [AWS ECS]                                          : terminate v2 task, DO NOT terminate old v1 tasks          : immediately
[AWS ECS] → [AWS ECS]                                          : retry launching new v2 task                               : ECS continuous reconciliation loop
```

> **Meanwhile (The Live System):**
```
[Smartphone] → [AWS IoT Core]                                  : live telemetry batches                                    : every 10 seconds
[AWS IoT Core] → [Telemetry Infrastructure v1]                 : live telemetry batches                                    : via rules engine
[Telemetry Infrastructure v1] → [Hot Storage]                  : write payloads normally                                   : business as usual
```

#### Monitoring and Resolution

```
[AWS ECS] → [CloudWatch]                                       : deployment state metric (failing to reach steady state)   : continuous event stream
[CloudWatch] → [SNS]                                           : deployment failure alarm                                  : on threshold breached
[SNS] → [PagerDuty]                                            : ECS deployment failing alert                              : immediately
[PagerDuty] → [Infrastructure Engineer]                        : page — Telemetry Infrastructure v2 deployment failing     : immediately
```

> **Result:** "Zero Downtime." Despite a catastrophic bug in the new application container, live telemetry routing is unaffected because the old container (`v1`) was never killed. The Engineer issues a `git revert` on the application code branch, and CI/CD pushes a corrected container.

---

### SQS Safety Net During Successful Swaps (Queue-Consumer Services Only)

> **Scope:** This safety net applies only to services that consume from SQS queues — **Processing Infrastructure** (reads from SQS Crash Queue and SQS LWT Queue) and **Alerting Infrastructure** (reads from SQS Alert Queue). It does NOT apply to **Telemetry Infrastructure**, which has no queue between itself and IoT Core. Telemetry Infra's protection during a swap is the rolling update itself keeping `v1` alive (see Known Limitations below).

```
[AWS ECS] → [Processing Infrastructure v1]                     : SIGTERM signal sent                                       : on v2 passing health check
[Processing Infrastructure v1] → [Processing Infrastructure v1]: finish processing current crash event message             : within 30s grace period
[Processing Infrastructure v1] → [SQS Crash Queue]             : acknowledge (delete) processed message                    : immediately
[Processing Infrastructure v1] → [AWS ECS]                     : exit complete                                             : on shutdown
[Telemetry Infrastructure v1] → [SQS Crash Queue]              : write new crash events                                    : continuous — v1 still alive and receiving IoT Core pushes
[SQS Crash Queue] → [SQS Crash Queue]                          : hold new messages during consumer gap                     : briefly during Processing Infra task swap
[AWS ECS] → [Processing Infrastructure v2]                     : start task, bind to queue                                 : immediately on v1 exit
[Processing Infrastructure v2] → [SQS Crash Queue]             : read piled-up messages                                    : on steady state
```

> **Result:** No crash flags are lost during a Processing or Alerting Infrastructure deployment. SQS acts as a shock absorber. If `v1` died unexpectedly without acknowledging a message, SQS makes that message visible again after the Visibility Timeout (configurable, e.g. 30 seconds), and `v2` reprocesses it.

---

### Known Limitations

#### No Queue Buffer Between IoT Core and Telemetry Infrastructure
Telemetry Infrastructure receives data directly from the IoT Core rules engine — there is no SQS queue between them. During a Telemetry Infrastructure rolling update, the rolling update itself is the sole protection: `minimum_healthy_percent = 100%` keeps `v1` alive until `v2` passes its health check. If `v1` crashes unexpectedly during a swap (not a clean shutdown), telemetry data in transit from IoT Core at that exact moment could be lost. 
>
> Adding an SQS Telemetry Queue between IoT Core and Telemetry Infrastructure would close this gap but is a meaningful architectural change (new queue, Telemetry Infra becomes a queue consumer, IoT Core rules engine writes to queue). Marked as a Future Enhancement — the Smartphone buffer already handles Telemetry Infra outages at the device layer (Flows 2B, 9F).

#### Database Migrations
This flow protects stateless ECS services. It does not map logic for a "Bad Database Migration" (e.g., dropping a critical column in Hot Storage). Database schema state failures are significantly harder to roll back than stateless application containers and would require restoring from snapshots, causing downtime that rolling updates cannot cover.

#### Misconfigured Health Check Path
If the Infrastructure Engineer makes a typo in the Terraform configuration for the ECS health check path (e.g., configures `/helt` instead of `/health`), even a perfectly good container will be marked UNHEALTHY by ECS because the health ping fails. ECS will infinitely cycle trying to boot the container, confusing the source of the error.

---

## Flow 9M — Monitoring Stack Failure (Observability Layer)

> **Precondition:** The AWS ECS cluster hosting the Monitoring Stack (Prometheus, Alertmanager, Grafana) experiences a catastrophic out-of-memory error, network isolation, or is accidentally deleted via a bad Terraform apply.
>
> **The Problem:** The system designed to alert the Infrastructure Engineer to failures is itself dead. This is a "Silent Failure" state — telemetry processes normally, but if a separate failure occurs inside AWS during this window, no alerts will be routed to PagerDuty.
>
> **The Solution (Dead Man's Switch):** An external 3rd-party uptime service (e.g., Healthchecks.io, UptimeRobot, or native PagerDuty heartbeats) is configured to expect a continuous heartbeat from the AWS environment. The alerting boundary stops at this 3rd-party service to prevent infinite loops of watchers watching watchers.
>
> **Grace Period:** The external service is configured with a 1-minute expected heartbeat interval and a 5-minute grace period. If 6 minutes pass without a ping, it triggers a PagerDuty incident directly from outside AWS.

---

### The Healthy Heartbeat State

> During normal operations, Prometheus proves the alerting pipeline is healthy by successfully routing a heartbeat through Alertmanager to the external internet.

```
[Prometheus] → [Alertmanager]                                  : generate synthetic `Watchdog` alert                       : continuous
[Alertmanager] → [Healthchecks.io]                             : HTTP GET request (heartbeat ping)                         : every 1 minute
[Healthchecks.io] → [Healthchecks.io]                          : record ping, reset 5-minute grace period timer            : immediately
```

> **Result:** The system is known to be healthy. The external service remains quiet.

---

### Monitoring Stack Failure & Alert Trigger

> The Monitoring ECS cluster crashes. The 1-minute heartbeats cease.

```
[AWS ECS] → [Prometheus/Alertmanager]                          : container crash / cluster down                            : unexpected event
[Alertmanager] → [Healthchecks.io]                             : HTTP GET request (heartbeat ping)                         : FAILS (stops sending)
[Healthchecks.io] → [Healthchecks.io]                          : 1 minute passes, 5-minute grace period begins             : on missed ping
[Healthchecks.io] → [Healthchecks.io]                          : grace period expires (6 minutes total silence)            : on timer expiry
[Healthchecks.io] → [PagerDuty]                                : CRITICAL — Dead Man's Switch Triggered                    : immediately
[PagerDuty] → [Infrastructure Engineer]                        : page — Monitoring Stack Down (Dead Man's Switch)          : immediately via SMS and call
```

> **Result:** The Infrastructure Engineer is alerted to the silent failure state without relying on any internal AWS alerting infrastructure.
>
> **Impact on Telemetry:** Zero. Helmet crash detection, SQS queues, and database writes continue to function perfectly. The system is "flying blind," but the core application is not degraded.

---

### Recovery and Auto-Resolution

> The Infrastructure Engineer investigates the AWS console, identifies the failure (e.g., out-of-memory error), and restarts the ECS tasks or reverts the bad Terraform commit.

```
[Infrastructure Engineer] → [AWS ECS]                          : restart Monitoring tasks / fix config                     : manual intervention
[AWS ECS] → [Prometheus/Alertmanager]                          : containers boot successfully                              : on restart
[Prometheus] → [Alertmanager]                                  : resume generating synthetic `Watchdog` alert              : immediately on boot
[Alertmanager] → [Healthchecks.io]                             : HTTP GET request (heartbeat ping)                         : successfully sent
[Healthchecks.io] → [Healthchecks.io]                          : record ping, mark monitor as UP                           : immediately
[Healthchecks.io] → [PagerDuty]                                : resolve CRITICAL — Dead Man's Switch Triggered            : immediately
[PagerDuty] → [Infrastructure Engineer]                        : alert resolved notification                               : immediately
```

> **Result:** The alerting pipeline is verified healthy again. The Dead Man's Switch auto-resolves purely by receiving the ping.

---

### Known Limitations

#### Blind Spot During the Outage
If a secondary failure occurs (e.g., Hot Storage goes down) *while* the Monitoring Stack is dead, the Infrastructure Engineer will not receive an alert for the secondary failure. They will only know the monitoring stack is down. The secondary failure will only become visible during the engineer's manual investigation or after the monitoring stack is brought back online and begins scraping health endpoints again.

#### Relying on a Single External Provider
If Healthchecks.io itself experiences a global outage at the exact same moment  AWS infrastructure crashes, the Dead Man's Switch will not fire to PagerDuty. This is an accepted industry risk

---

## Flow 10 — Firmware Update

> **Precondition:** A new firmware version has been prepared and uploaded to S3 by the firmware engineering team. The Fleet Manager initiates the rollout via AWS IoT Device Management.
>
> **Rollout strategy:** Canary deployment. 10% of the fleet receives the update first (canary group). The observation window is threshold-based — full fleet rollout proceeds automatically once the canary group passes the observation window with no anomalies detected. Abort criteria are set on the job upfront — if the failure rate across devices in any batch exceeds the configured threshold, the job halts immediately and only devices that have already installed the update are rolled back. Devices that have not yet received the package are untouched.
>
> **Install timing:** The firmware package is delivered OTA via IoT Core → Smartphone → Helmet. The helmet stages the package locally but does not apply it during the current session. The update installs on the next helmet power cycle. The updated firmware version is confirmed via the firmware version field in the first telemetry payload after restart.
>
> **Previous stable firmware version** is retained in S3 at all times. Rollback is executed by pushing the previous stable version as a new AWS IoT Job — not a special undo operation.
>
> **Abort criteria** are configured by the Fleet Manager at job creation time. The exact failure rate threshold is a Fleet Manager operational decision and is not hardcoded in infrastructure.
>
> **Cross-reference:** Flow 9K covers the *detection and response* to a bad firmware update (installation failure and behavioural anomaly). Flow 10 covers the *operational lifecycle* of a firmware rollout — job creation, canary delivery, observation, full fleet rollout, and rollback mechanics. Flow 10 supersedes the install timing model in Flow 9K: firmware is staged on delivery and applied on next power cycle, rather than installed immediately.

---

### Job Creation

```
[Fleet Manager] → [AWS IoT Device Management]           : create firmware rollout job, new firmware version, S3 firmware package URI, canary percentage (10%), abort criteria threshold, observation window duration : on new firmware release
[AWS IoT Device Management] → [Cold Storage]            : query canary group device IDs, current stable firmware version                                        : immediately
[Cold Storage] → [AWS IoT Device Management]            : canary group device IDs, current stable firmware version                                              : immediately
[AWS IoT Device Management] → [AWS IoT Device Management] : job created, canary group targeted, abort criteria armed, observation window timer set               : immediately
```

---

### Canary Package Delivery

```
[AWS IoT Device Management] → [AWS IoT Core]            : firmware update job, canary group device IDs, S3 firmware package URI                                 : immediately on job creation
[AWS IoT Core] → [Smartphone]                           : firmware update package, new firmware version identifier, helmet ID                                    : via helmet/{helmet_id}/firmware/update topic
[Smartphone] → [Helmet — Canary Group]                  : firmware update package, new firmware version identifier                                               : immediately via Bluetooth
[Helmet — Canary Group] → [Helmet — Canary Group]       : stage firmware package locally — do not install                                                        : on package received
[Helmet — Canary Group] → [Smartphone]                  : package staged acknowledgement, device ID, firmware version, timestamp                                 : immediately
[Smartphone] → [AWS IoT Core]                           : package staged acknowledgement, device ID, firmware version, timestamp                                 : immediately via helmet/{helmet_id}/firmware/status topic
[AWS IoT Core] → [AWS IoT Device Management]            : package staged acknowledgement, device ID, firmware version, timestamp                                 : immediately via rules engine
```

---

### Canary Install Confirmation (Next Power Cycle)

> Rider powers the helmet off and back on at a later time. The helmet applies the staged firmware during startup before resuming normal operation. The updated firmware version appears in the first telemetry payload of the new session.

```
[Helmet — Canary Group] → [Helmet — Canary Group]       : apply staged firmware on startup                                                                       : on next power cycle
[Helmet — Canary Group] → [Smartphone]                  : install status — success or failure, device ID, new firmware version, timestamp                        : on install attempt complete
[Smartphone] → [AWS IoT Core]                           : install status, device ID, new firmware version, timestamp                                              : immediately via helmet/{helmet_id}/firmware/status topic
[AWS IoT Core] → [AWS IoT Device Management]            : install status — success or failure, device ID, new firmware version, timestamp                        : immediately via rules engine
[AWS IoT Device Management] → [AWS IoT Device Management] : update installed device count and failure count against abort criteria                                : on each status report received
```

> Install confirmation is also passively verified through normal telemetry — the firmware version field in every telemetry payload reflects the active firmware version. Processing Infrastructure uses this field during the observation window for anomaly correlation (see Flow 9K Branch B).

---

### Observation Window

> All canary group devices have reported successful installation. AWS IoT Device Management starts the observation window timer. Processing Infrastructure monitors crash flag rates correlated against the new firmware version via the normal telemetry pipeline throughout this window.

```
[AWS IoT Device Management] → [AWS IoT Device Management] : all canary installs confirmed, start observation window timer                                         : on all canary install success reports received
[AWS IoT Device Management] → [AWS IoT Device Management] : observation window active — monitoring for halt signal from Processing Infrastructure                  : continuously until timer expiry
```

#### Branch A — Observation Window Passes (Happy Path)

```
[AWS IoT Device Management] → [AWS IoT Device Management] : observation window expired, no halt signal received, proceed to full fleet rollout                    : on timer expiry
```

> Cross-reference: If Processing Infrastructure detects a behavioural anomaly during the observation window, it sends a halt signal to AWS IoT Device Management. That path is fully defined in Flow 9K Branch B and is not repeated here.

---

### Full Fleet Rollout

> Same delivery and install confirmation path as canary. Abort criteria remain armed throughout. AWS IoT Device Management monitors the failure rate live — if the threshold is breached at any point during rollout, the job halts immediately.

```
[AWS IoT Device Management] → [AWS IoT Core]            : firmware update job, remaining fleet device IDs, S3 firmware package URI                               : immediately on observation window pass
[AWS IoT Core] → [Smartphone]                           : firmware update package, new firmware version identifier, helmet ID                                    : via helmet/{helmet_id}/firmware/update topic
[Smartphone] → [Helmet — Remaining Fleet]               : firmware update package, new firmware version identifier                                               : immediately via Bluetooth
[Helmet — Remaining Fleet] → [Helmet — Remaining Fleet] : stage firmware package locally — do not install                                                        : on package received
[Helmet — Remaining Fleet] → [Smartphone]               : package staged acknowledgement, device ID, firmware version, timestamp                                 : immediately
[Smartphone] → [AWS IoT Core]                           : package staged acknowledgement, device ID, firmware version, timestamp                                 : immediately via helmet/{helmet_id}/firmware/status topic
[AWS IoT Core] → [AWS IoT Device Management]            : package staged acknowledgement, device ID, firmware version, timestamp                                 : immediately via rules engine
[Helmet — Remaining Fleet] → [Helmet — Remaining Fleet] : apply staged firmware on startup                                                                       : on next power cycle per device
[Helmet — Remaining Fleet] → [Smartphone]               : install status — success or failure, device ID, new firmware version, timestamp                        : on install attempt complete
[Smartphone] → [AWS IoT Core]                           : install status, device ID, new firmware version, timestamp                                              : immediately via helmet/{helmet_id}/firmware/status topic
[AWS IoT Core] → [AWS IoT Device Management]            : install status — success or failure, device ID, new firmware version, timestamp                        : immediately via rules engine
[AWS IoT Device Management] → [AWS IoT Device Management] : update installed device count and failure count against abort criteria                                : on each status report received
```

---

### Branch B — Abort Criteria Breached During Full Fleet Rollout

> The failure rate across devices that have received the update crosses the abort criteria threshold mid-rollout. The job halts immediately. Devices that have not yet received the package are untouched. Only devices that have already installed the new firmware are rolled back.

```
[AWS IoT Device Management] → [AWS IoT Device Management] : failure count breaches abort criteria threshold — halt job                                            : immediately on threshold breach
[AWS IoT Device Management] → [AWS IoT Device Management] : cancel pending deliveries to all remaining untouched devices                                          : immediately
[AWS IoT Device Management] → [AWS IoT Core]            : rollback job, device IDs of installed devices only, previous stable firmware S3 URI                    : immediately
[AWS IoT Core] → [Smartphone]                           : rollback package, previous stable firmware version identifier, helmet ID                               : via helmet/{helmet_id}/firmware/update topic
[Smartphone] → [Helmet]                                 : rollback package, previous stable firmware version identifier                                           : immediately via Bluetooth
[Helmet] → [Helmet]                                     : stage rollback package locally — do not install                                                         : on package received
[Helmet] → [Smartphone]                                 : package staged acknowledgement, device ID, previous stable firmware version, timestamp                  : immediately
[Smartphone] → [AWS IoT Core]                           : package staged acknowledgement, device ID, previous stable firmware version, timestamp                  : immediately via helmet/{helmet_id}/firmware/status topic
[AWS IoT Core] → [AWS IoT Device Management]            : package staged acknowledgement, device ID, previous stable firmware version, timestamp                  : immediately via rules engine
[Helmet] → [Helmet]                                     : apply staged rollback firmware on startup                                                               : on next power cycle
[Helmet] → [Smartphone]                                 : rollback install status — success, device ID, previous stable firmware version, timestamp               : on rollback install complete
[Smartphone] → [AWS IoT Core]                           : rollback install status, device ID, previous stable firmware version, timestamp                         : immediately via helmet/{helmet_id}/firmware/status topic
[AWS IoT Core] → [AWS IoT Device Management]            : rollback install status — success, device ID, previous stable firmware version, timestamp               : immediately via rules engine
```

#### Monitoring and Alerting — Abort Criteria Breached

```
[CloudWatch] → [CloudWatch]                             : firmware rollout abort metric, new firmware version, failure count, devices affected, timestamp         : on job halted
[CloudWatch] → [SNS]                                    : firmware rollout abort alarm, new firmware version, failure count, timestamp                            : immediately on alarm threshold
[SNS] → [PagerDuty]                                     : firmware rollout aborted, new firmware version, failure count, timestamp                                : immediately
[PagerDuty] → [Fleet Manager]                           : page — firmware rollout aborted, new firmware version, failure count, devices affected, timestamp       : immediately via SMS and call
[PagerDuty] → [Infrastructure Engineer]                 : page — firmware rollout aborted, new firmware version, failure count, timestamp                         : immediately via SMS and call
```

> Devices that never received the package remain on the current stable firmware and are unaffected. Devices that installed the new firmware are rolled back to the previous stable version. Fleet returns to a fully known stable state.

---

### Branch C — Fleet Manager Manual Rollback

> The Fleet Manager identifies a problem independently — via dashboard review, rider reports, or any out-of-band signal — and decides to roll back without waiting for abort criteria to fire automatically.

```
[Fleet Manager] → [AWS IoT Device Management]           : cancel active rollout job                                                                               : manual decision
[AWS IoT Device Management] → [AWS IoT Device Management] : cancel pending deliveries to all remaining untouched devices                                          : immediately
[Fleet Manager] → [AWS IoT Device Management]           : create rollback job, device IDs of installed devices, previous stable firmware S3 URI                   : immediately
[AWS IoT Device Management] → [AWS IoT Core]            : rollback job, device IDs of installed devices, previous stable firmware S3 URI                          : immediately
[AWS IoT Core] → [Smartphone]                           : rollback package, previous stable firmware version identifier, helmet ID                               : via helmet/{helmet_id}/firmware/update topic
[Smartphone] → [Helmet]                                 : rollback package, previous stable firmware version identifier                                           : immediately via Bluetooth
[Helmet] → [Helmet]                                     : stage rollback package locally — do not install                                                         : on package received
[Helmet] → [Smartphone]                                 : package staged acknowledgement, device ID, previous stable firmware version, timestamp                  : immediately
[Smartphone] → [AWS IoT Core]                           : package staged acknowledgement, device ID, previous stable firmware version, timestamp                  : immediately via helmet/{helmet_id}/firmware/status topic
[AWS IoT Core] → [AWS IoT Device Management]            : package staged acknowledgement, device ID, previous stable firmware version, timestamp                  : immediately via rules engine
[Helmet] → [Helmet]                                     : apply staged rollback firmware on startup                                                               : on next power cycle
[Helmet] → [Smartphone]                                 : rollback install status — success, device ID, previous stable firmware version, timestamp               : on rollback install complete
[Smartphone] → [AWS IoT Core]                           : rollback install status, device ID, previous stable firmware version, timestamp                         : immediately via helmet/{helmet_id}/firmware/status topic
[AWS IoT Core] → [AWS IoT Device Management]            : rollback install status — success, device ID, previous stable firmware version, timestamp               : immediately via rules engine
```

> Manual rollback follows the same delivery path as abort-triggered rollback. The difference is the trigger — Fleet Manager decision rather than automated threshold breach.

---

### On Rollout Complete (Happy Path)

```
[AWS IoT Device Management] → [Cold Storage]            : firmware rollout record, new firmware version, rollout completed, all devices updated, timestamp        : on all install success reports received
[CloudWatch] → [CloudWatch]                             : firmware rollout complete metric, new firmware version, all devices confirmed, timestamp                 : on all install success reports received
[CloudWatch] → [SNS]                                    : firmware rollout complete notification, new firmware version, timestamp                                  : immediately
[SNS] → [Fleet Manager]                                 : firmware rollout complete, new firmware version, all devices updated, timestamp                          : immediately via email
```

> No paging on happy path completion — rollout complete is a low-urgency notification, not an incident. SNS routes directly to Fleet Manager email, not PagerDuty.

---

### On Rollback Complete (Branches B and C)

```
[AWS IoT Device Management] → [Cold Storage]            : firmware rollback record, new firmware version, rollback reason — abort criteria or manual, devices affected, timestamp : on all rollback confirmations received
[CloudWatch] → [CloudWatch]                             : rollback complete metric, all affected devices on stable firmware, timestamp                             : on all rollback confirmations received
[CloudWatch] → [SNS]                                    : rollback complete alarm resolved, timestamp                                                              : immediately
[SNS] → [PagerDuty]                                     : rollback complete, timestamp                                                                            : immediately
[PagerDuty] → [Fleet Manager]                           : rollback complete, all affected devices on stable firmware, timestamp                                   : immediately
[PagerDuty] → [Infrastructure Engineer]                 : rollback complete, timestamp                                                                            : immediately
```

> No further automated action. Re-release of a fixed firmware version is a separate, manually initiated process by the Fleet Manager. The failed firmware version is not retried automatically.

---

### Known Limitations

#### Rollback depends on next power cycle
Both the new firmware install and the rollback apply at next helmet power cycle — not immediately. A helmet that has staged a bad firmware package but not yet restarted will install the bad firmware on its next power cycle even after a rollback job has been issued, if the rollback package has not yet been staged over it. The rollback package overwrites the staged update as soon as it is delivered, but delivery requires IoT Core and Smartphone to be available.

#### No install confirmation from helmets that never power cycle
A device that stages the firmware package but never restarts will never report an install status. AWS IoT Device Management will show it as `staged` indefinitely. The Fleet Manager must account for this in rollout completion reporting — 100% install confirmation is not guaranteed within any fixed timeframe.

#### Rollback scope is install-confirmed devices only
Abort criteria and manual rollback both target only devices that have confirmed installation. Devices that staged the package but not yet installed retain the staged package. If they restart after rollback is complete, they may install the bad firmware. Fleet Manager must cancel the original job cleanly to prevent staged packages from being applied.

---

## Flow 11 — Scale Up / Scale Down

> **Precondition:** The Smart Helmet fleet generates variable traffic volumes throughout the day. During commuter rush hours (7–10 AM, 5–9 PM), the majority of the fleet is active and streaming telemetry simultaneously. During off-peak hours (midday, overnight), most helmets are powered off. Infrastructure must scale dynamically to handle peak load without over-provisioning during quiet periods.
>
> **Two scaling strategies combined:** Scheduled scaling pre-provisions capacity before known traffic peaks — eliminates cold-start lag. Reactive scaling responds to live metrics for unexpected spikes — catches edge cases that scheduled scaling misses (mass events, gradual traffic growth).
>
> **Scaling boundaries:** Minimum 2 instances per ECS service at all times — single instance is a single point of failure. Maximum 5 instances per service — cost ceiling for a portfolio/demo project with a fleet of ~100 helmets.
>
> **Components that do NOT scale:** IoT Core (AWS-managed, scales automatically), SQS queues (AWS-managed, unlimited throughput), Cold Storage (low-frequency writes, fixed provisioned capacity), Monitoring Stack (single ECS instance, known limitation).
>
> **Cooldown period:** 30 minutes after any scaling event before the next scale-in is permitted. Prevents flapping (rapid up-down-up-down oscillation). Production-grade cooldown values would be tuned based on traffic analytics.

---

### Traffic Distribution — ALB in Front of Telemetry Infrastructure

> IoT Core rules engine delivers telemetry batches to Telemetry Infrastructure via an HTTP action targeting an Application Load Balancer (ALB). The ALB distributes incoming traffic across all healthy Telemetry Infra ECS tasks using round-robin routing. This is the foundational mechanism that enables Telemetry Infrastructure to scale horizontally.

```
[AWS IoT Core] → [ALB]                                  : telemetry batch, helmet ID                                                                             : immediately via IoT Core rules engine HTTP action
[ALB] → [Telemetry Infrastructure — ECS Task]            : telemetry batch, helmet ID                                                                             : round-robin distribution across healthy targets
[Telemetry Infrastructure — ECS Task] → [Hot Storage (DynamoDB)] : write telemetry batch                                                                         : on every receive
[Telemetry Infrastructure — ECS Task] → [SQS Crash Queue] : crash event data point, firmware version, helmet ID, timestamp                                       : if crash flag found in batch
[Telemetry Infrastructure — ECS Task] → [SQS Control Queue] : control message data point (shutdown, low battery, battery death)                                  : if control event found in batch
```

> ALB also provides health checks — unhealthy ECS tasks are automatically removed from rotation. During scale-down, ALB drains in-flight connections before deregistering a task (deregistration delay — default 300 seconds).

---

### Scheduled Scaling

> Scheduled scaling pre-provisions capacity before predictable traffic peaks. ECS Application Auto Scaling supports scheduled actions that adjust desired task count on a cron schedule.

```
[ECS Application Auto Scaling] → [Telemetry Infrastructure]  : scale to 4 tasks                                                                                  : 06:45 AM daily (15 min before morning rush)
[ECS Application Auto Scaling] → [Processing Infrastructure] : scale to 3 tasks                                                                                  : 06:45 AM daily
[ECS Application Auto Scaling] → [Alerting Infrastructure]   : scale to 3 tasks                                                                                  : 06:45 AM daily
[ECS Application Auto Scaling] → [Telemetry Infrastructure]  : scale to 4 tasks                                                                                  : 04:45 PM daily (15 min before evening rush)
[ECS Application Auto Scaling] → [Processing Infrastructure] : scale to 3 tasks                                                                                  : 04:45 PM daily
[ECS Application Auto Scaling] → [Alerting Infrastructure]   : scale to 3 tasks                                                                                  : 04:45 PM daily
[ECS Application Auto Scaling] → [Telemetry Infrastructure]  : scale to 2 tasks (minimum)                                                                        : 10:30 AM daily (after morning rush)
[ECS Application Auto Scaling] → [Processing Infrastructure] : scale to 2 tasks (minimum)                                                                        : 10:30 AM daily
[ECS Application Auto Scaling] → [Alerting Infrastructure]   : scale to 2 tasks (minimum)                                                                        : 10:30 AM daily
[ECS Application Auto Scaling] → [Telemetry Infrastructure]  : scale to 2 tasks (minimum)                                                                        : 09:30 PM daily (after evening rush)
[ECS Application Auto Scaling] → [Processing Infrastructure] : scale to 2 tasks (minimum)                                                                        : 09:30 PM daily
[ECS Application Auto Scaling] → [Alerting Infrastructure]   : scale to 2 tasks (minimum)                                                                        : 09:30 PM daily
```

> Telemetry Infrastructure gets the highest scheduled count (4) because it handles every telemetry batch from every active helmet. Processing and Alerting Infra get 3 because they only handle crash events and control messages — a fraction of total telemetry volume.
>
> Scheduled actions fire 15 minutes before the rush window to give tasks time to start and register with the ALB or begin polling SQS.

---

### Reactive Scaling — Telemetry Infrastructure

> Telemetry Infrastructure is write-heavy, not compute-heavy. CPU utilization is a poor scaling signal — it stays low even under load because the bottleneck is I/O (writes to DynamoDB and SQS), not computation. The correct signal is ALB request count per target.

```
[CloudWatch] → [CloudWatch]                             : ALB request count per target metric, current value, timestamp                                          : continuously
[CloudWatch] → [ECS Application Auto Scaling]           : ALB request count per target exceeds threshold                                                         : on threshold breach
[ECS Application Auto Scaling] → [ECS]                  : increase Telemetry Infrastructure desired count by 1, up to maximum 5                                  : immediately
[ECS] → [Telemetry Infrastructure — New Task]           : start new task, register with ALB target group                                                          : task startup time (~60–90 seconds)
[ALB] → [Telemetry Infrastructure — New Task]           : begin routing traffic to new task after health check passes                                             : on first successful health check
```

> Reactive scaling supplements scheduled scaling — it catches unexpected spikes that exceed scheduled capacity. Both policies coexist; ECS uses the higher desired count from either policy.

---

### Reactive Scaling — Processing Infrastructure

> Processing Infrastructure is a queue consumer. It reads from SQS Crash Queue, SQS Control Queue, and SQS LWT Queue. The correct scaling signal is the maximum queue depth across all three queues — if any queue is backing up, more tasks are needed.

```
[CloudWatch] → [CloudWatch]                             : SQS ApproximateNumberOfMessagesVisible metric — Crash Queue, Control Queue, LWT Queue                   : every 60 seconds
[CloudWatch] → [ECS Application Auto Scaling]           : maximum queue depth across three queues exceeds threshold                                               : on threshold breach
[ECS Application Auto Scaling] → [ECS]                  : increase Processing Infrastructure desired count by 1, up to maximum 5                                 : immediately
[ECS] → [Processing Infrastructure — New Task]          : start new task, begin polling SQS queues                                                                : task startup time (~60–90 seconds)
```

> Processing Infrastructure also scales on CPU utilization at 70% as a secondary signal — crash validation involves DynamoDB reads and threshold comparisons that can become compute-bound during a mass event.

---

### Reactive Scaling — Alerting Infrastructure

> Alerting Infrastructure reads from SQS Alert Queue. Each message spawns an independent AWS Step Functions execution for the alert lifecycle (5-sec override window or 30-sec countdown). The ECS task itself does not wait — it dequeues, starts a Step Function, and moves on. Step Functions is serverless and scales automatically.

```
[CloudWatch] → [CloudWatch]                             : SQS ApproximateNumberOfMessagesVisible metric — Alert Queue                                             : every 60 seconds
[CloudWatch] → [ECS Application Auto Scaling]           : Alert Queue depth exceeds threshold                                                                     : on threshold breach
[ECS Application Auto Scaling] → [ECS]                  : increase Alerting Infrastructure desired count by 1, up to maximum 5                                   : immediately
[ECS] → [Alerting Infrastructure — New Task]            : start new task, begin polling SQS Alert Queue                                                           : task startup time (~60–90 seconds)
```

> Alerting Infrastructure is the lowest-traffic service — it only handles confirmed crash events and false positives requiring rider interaction. The majority of telemetry batches contain no crash flag and never reach this stage.

---

### Reactive Scaling — Hot Storage (DynamoDB Auto-Scaling)

> Hot Storage uses DynamoDB with auto-scaling enabled on both Read Capacity Units (RCUs) and Write Capacity Units (WCUs). Target utilization is set to 70% — DynamoDB automatically adjusts capacity when utilization crosses this threshold. Storage capacity is unlimited — DynamoDB never runs out of space.

```
[DynamoDB Auto-Scaling] → [DynamoDB]                    : write utilization exceeds 70% target — increase WCUs                                                   : automatically on sustained breach
[DynamoDB Auto-Scaling] → [DynamoDB]                    : read utilization exceeds 70% target — increase RCUs                                                    : automatically on sustained breach
[DynamoDB Auto-Scaling] → [DynamoDB]                    : write utilization below 70% target — decrease WCUs                                                     : automatically after sustained drop (cooldown applies)
[DynamoDB Auto-Scaling] → [DynamoDB]                    : read utilization below 70% target — decrease RCUs                                                      : automatically after sustained drop (cooldown applies)
```

> Write capacity scales with Telemetry Infrastructure traffic — more ECS tasks writing concurrently means higher WCU demand. Read capacity scales with Processing Infrastructure activity — crash validation reads recent telemetry history from Hot Storage.
>
> DynamoDB TTL handles the 24-hour expiry natively — records are deleted automatically after their TTL attribute expires. No manual cleanup needed.

---

### Scale-Down Mechanics

> Scale-down is more dangerous than scale-up. Removing capacity too aggressively can cause message loss, in-flight request failures, or service degradation. Scale-down follows a strict sequence: metric drop detected → cooldown check → scale-in decision → graceful task termination → minimum instance floor enforced.

#### Cooldown Period

```
[ECS Application Auto Scaling] → [ECS Application Auto Scaling] : scaling event completed — start 30-minute cooldown timer                                       : on any scale-up or scale-down event
[ECS Application Auto Scaling] → [ECS Application Auto Scaling] : scale-in request received during cooldown — rejected                                              : if cooldown timer has not expired
[ECS Application Auto Scaling] → [ECS Application Auto Scaling] : cooldown expired — scale-in permitted if metrics support it                                       : on cooldown timer expiry
```

> Cooldown prevents flapping — rapid scale-up/scale-down oscillation that wastes resources and causes instability. The 30-minute window ensures traffic has genuinely stabilised before removing capacity.
>
> **Scheduled vs cooldown conflict:** Scheduled actions in ECS Application Auto Scaling bypass the reactive cooldown and execute on their cron trigger regardless of recent scaling activity. If a reactive scale-up fired shortly before a scheduled scale-down, the scheduled action will still fire and temporarily reduce capacity. However, the reactive target tracking policy will re-evaluate within its next evaluation period (~60 seconds) and scale back up if the metric still demands it. The brief capacity dip is accepted behaviour — it self-corrects within seconds.

#### Scaling Policy Conflict Resolution

> When multiple scaling policies (scheduled + reactive) are active simultaneously, ECS Application Auto Scaling uses the **highest desired count** from any active policy. This ensures safety — the system may briefly over-provision but will never under-provision when there is active demand. The only exception is the scheduled vs cooldown edge case documented above, where a scheduled action can briefly override a reactive scale-up before the reactive policy self-corrects.

---

#### Scale-Down Triggers Per Component

> Each component scales down when its scaling signal drops below threshold for a sustained period AND the cooldown has expired AND the current task count is above the minimum (2).

##### Telemetry Infrastructure

```
[CloudWatch] → [CloudWatch]                             : ALB request count per target below threshold for sustained period                                        : continuously monitored
[CloudWatch] → [ECS Application Auto Scaling]           : ALB request count per target below scale-down threshold                                                  : on sustained drop detected
[ECS Application Auto Scaling] → [ECS Application Auto Scaling] : check cooldown timer — expired                                                                 : before proceeding
[ECS Application Auto Scaling] → [ECS Application Auto Scaling] : check current task count — above minimum (2)                                                    : before proceeding
[ECS Application Auto Scaling] → [ECS]                  : decrease Telemetry Infrastructure desired count by 1                                                      : on all checks passed
```

##### Processing Infrastructure

```
[CloudWatch] → [CloudWatch]                             : all three SQS queue depths below threshold AND CPU utilization below 70% for sustained period             : continuously monitored
[CloudWatch] → [ECS Application Auto Scaling]           : queue depth and CPU both below scale-down thresholds                                                      : on sustained drop detected
[ECS Application Auto Scaling] → [ECS Application Auto Scaling] : check cooldown timer — expired                                                                 : before proceeding
[ECS Application Auto Scaling] → [ECS Application Auto Scaling] : check current task count — above minimum (2)                                                    : before proceeding
[ECS Application Auto Scaling] → [ECS]                  : decrease Processing Infrastructure desired count by 1                                                     : on all checks passed
```

##### Alerting Infrastructure

```
[CloudWatch] → [CloudWatch]                             : SQS Alert Queue depth below threshold for sustained period                                                : continuously monitored
[CloudWatch] → [ECS Application Auto Scaling]           : Alert Queue depth below scale-down threshold                                                               : on sustained drop detected
[ECS Application Auto Scaling] → [ECS Application Auto Scaling] : check cooldown timer — expired                                                                 : before proceeding
[ECS Application Auto Scaling] → [ECS Application Auto Scaling] : check current task count — above minimum (2)                                                    : before proceeding
[ECS Application Auto Scaling] → [ECS]                  : decrease Alerting Infrastructure desired count by 1                                                        : on all checks passed
```

> Scale-down removes one task at a time — never multiple tasks simultaneously. After each removal, the cooldown timer restarts. This prevents aggressive scale-in from destabilising the service.

---

#### ECS Scale-In Protection — Queue Consumers (Processing and Alerting Infra)

> When ECS decides to terminate a task during scale-down, the task may be mid-processing an SQS message. Two mechanisms protect against message loss. **The same mechanics apply identically to both Processing Infrastructure and Alerting Infrastructure** — both are SQS queue consumers with the same graceful shutdown behaviour.

```
[ECS] → [Queue Consumer Task]                           : SIGTERM signal — stop gracefully                                                                          : on scale-in decision
[Queue Consumer Task] → [Queue Consumer Task]           : stop polling SQS for new messages                                                                         : immediately on SIGTERM received
[Queue Consumer Task] → [Queue Consumer Task]           : finish processing current message                                                                          : within stopTimeout window (60 seconds)
[Queue Consumer Task] → [SQS]                           : delete processed message from queue                                                                        : on processing complete
[Queue Consumer Task] → [ECS]                           : exit cleanly                                                                                               : on all in-flight work complete
```

> **stopTimeout** is set to 60 seconds — the maximum time ECS waits for a task to exit after sending SIGTERM. If the task does not exit within 60 seconds, ECS sends SIGKILL (forced termination).
>
> **SQS Visibility Timeout** is set to 60 seconds — if a task is killed mid-processing before deleting the message, the message becomes invisible for 60 seconds and then reappears in the queue. Another task picks it up. No message is ever lost. This is at-least-once delivery — a message may be processed twice in the worst case, but idempotency design (duplicate detection via timestamp range) handles this.
>
> This applies to: Processing Infrastructure (reads from Crash, Control, and LWT queues) and Alerting Infrastructure (reads from Alert Queue). Both services implement the same SIGTERM handler.

#### ALB Connection Draining — Telemetry Infrastructure

> When ECS removes a Telemetry Infra task during scale-down, the ALB drains in-flight HTTP connections before deregistering the task.

```
[ECS] → [ALB]                                           : deregister Telemetry Infrastructure task from target group                                                : on scale-in decision
[ALB] → [ALB]                                           : stop routing NEW requests to deregistering task                                                            : immediately
[ALB] → [Telemetry Infrastructure — Task]               : allow in-flight requests to complete within deregistration delay (300 seconds)                            : during draining window
[Telemetry Infrastructure — Task] → [ECS]               : exit cleanly after all in-flight requests complete                                                        : on draining complete or timeout
```

> Telemetry batches are small, fast operations (write to DynamoDB, check for crash flag). In-flight requests complete in seconds. The 300-second deregistration delay is generous overhead — no telemetry batch is lost during scale-down.

---

#### Minimum Instance Floor

```
[ECS Application Auto Scaling] → [ECS Application Auto Scaling] : scale-in request would reduce task count below minimum (2) — rejected                           : on any scale-in attempt
```

> The minimum of 2 instances per service is a hard floor. ECS Application Auto Scaling enforces this via the `min_capacity` parameter on the auto-scaling target. No scaling policy, scheduled action, or reactive trigger can reduce task count below this value. This ensures basic redundancy at all times — if one task crashes, the other continues serving.

---

### Where Scaling Thresholds Live

> **Scaling thresholds are NOT stored in Parameter Store.** They are infrastructure configuration, not application configuration.

| Threshold Type | Where It Lives | Changed By |
|---|---|---|
| **Application thresholds** (crash detection, mass alert, firmware anomaly, battery %, TTL, cache refresh interval) | Parameter Store | Application code reads at runtime — can change without redeployment |
| **Scaling thresholds** (ALB request count target, SQS queue depth target, CPU target %, DynamoDB RCU/WCU utilization target) | Auto-scaling policies in Terraform | `terraform apply` — infrastructure change via CI/CD pipeline |
| **Scaling boundaries** (min/max instance count, cooldown period, stopTimeout, visibility timeout, deregistration delay) | ECS service and auto-scaling configuration in Terraform | `terraform apply` — infrastructure change via CI/CD pipeline |
| **Scheduled scaling times** (06:45 AM, 04:45 PM, 10:30 AM, 09:30 PM) | Scheduled actions in Terraform | `terraform apply` — infrastructure change via CI/CD pipeline |

> The distinction: your application code never reads scaling thresholds — AWS auto-scaling reads them directly from the policies you define in Terraform. Changing a scaling threshold is an infrastructure change, not an application change. It goes through the same CI/CD pipeline as any other Terraform modification (validate → plan → apply).

---

### Components That Do NOT Scale

#### AWS IoT Core

> Fully managed by AWS. Scales automatically to handle connection and message throughput. No capacity provisioning required. The only operational concern is **service quotas** — default limits on concurrent connections and messages per second per account. If the fleet exceeds default quotas, a quota increase is requested from AWS. Monitored via CloudWatch.

#### SQS Queues

> Fully managed by AWS. Unlimited throughput, unlimited queue depth. No capacity provisioning required. Queue depth is used as a **scaling signal** for consumer services (Processing and Alerting Infra), but SQS itself never needs scaling.

#### Cold Storage

> Low-frequency writes — incident records, logs, user data, firmware rollout records. Fixed provisioned capacity or DynamoDB on-demand mode is sufficient. Does not experience the traffic volume or variability that Hot Storage does.

#### Monitoring Stack (Prometheus, Alertmanager, Grafana)

> Single ECS instance. Prometheus scrapes ECS task health endpoints — the number of scrape targets is the number of ECS tasks (single-digit to low double-digit), not the number of helmets. CloudWatch handles IoT Core and DynamoDB metrics natively. For a portfolio project, a single monitoring instance is accepted as a known limitation.

---

### Scaling Configuration Summary

| Component | Scales | Signal (Up) | Signal (Down) | Min | Max | Type |
|---|---|---|---|---|---|---|
| Telemetry Infra (ECS) | Yes | ALB request count per target above threshold | ALB request count per target below threshold (sustained) | 2 | 5 | Scheduled + Reactive |
| Processing Infra (ECS) | Yes | Max SQS queue depth + CPU above 70% | All queue depths + CPU below threshold (sustained) | 2 | 5 | Scheduled + Reactive |
| Alerting Infra (ECS) | Yes | SQS Alert Queue depth above threshold | Alert Queue depth below threshold (sustained) | 2 | 5 | Scheduled + Reactive |
| Hot Storage (DynamoDB) | Yes | RCU/WCU utilization above 70% | RCU/WCU utilization below 70% (sustained) | N/A | N/A | DynamoDB auto-scaling |
| IoT Core | No | AWS-managed | AWS-managed | — | — | — |
| SQS Queues | No | AWS-managed | AWS-managed | — | — | — |
| Cold Storage | No | Fixed / on-demand | N/A | — | — | — |
| Monitoring Stack | No | Single instance | N/A | 1 | 1 | Known limitation |

| Parameter | Value | Defined In |
|---|---|---|
| Cooldown period | 30 minutes | Terraform (auto-scaling policy) |
| ECS stopTimeout | 60 seconds | Terraform (ECS task definition) |
| SQS visibility timeout | 60 seconds | Terraform (SQS queue configuration) |
| ALB deregistration delay | 300 seconds | Terraform (ALB target group) |
| DynamoDB target utilization | 70% (read and write) | Terraform (DynamoDB auto-scaling policy) |
| Scheduled scale-up | 06:45 AM and 04:45 PM daily | Terraform (scheduled scaling actions) |
| Scheduled scale-down | 10:30 AM and 09:30 PM daily | Terraform (scheduled scaling actions) |
| Min ECS tasks per service | 2 | Terraform (auto-scaling target min_capacity) |
| Max ECS tasks per service | 5 | Terraform (auto-scaling target max_capacity) |

---

### Known Limitations

#### Reactive scaling lag
New ECS tasks take 60–90 seconds to start and register. During this window, existing tasks absorb the full load spike. Scheduled scaling mitigates this for predictable peaks, but unexpected spikes (mass crash event) will experience a brief period of elevated latency before new tasks are available.

#### Cooldown values are not data-driven
The 30-minute cooldown period is a reasonable default but is not tuned to actual traffic patterns. Production-grade deployment would use traffic analytics to determine optimal cooldown values per service.

#### Monitoring stack does not scale
A single Prometheus instance scrapes all ECS task endpoints. If the number of ECS tasks grows significantly beyond the portfolio project scope, Prometheus may need horizontal scaling (e.g., Thanos or Prometheus federation). Accepted as a known limitation for this project.

#### DynamoDB auto-scaling has lag
DynamoDB auto-scaling reacts to sustained utilization changes, not instantaneous spikes. A sudden burst of writes (e.g., mass crash event generating thousands of telemetry writes simultaneously) may experience throttling for 1–2 minutes before capacity adjusts. DynamoDB burst capacity (unused capacity credits) partially mitigates this.

#### No auto-scaling for Step Functions
Step Functions is serverless and handles concurrency automatically. However, the maximum concurrent executions per account is subject to AWS service quotas. A mass crash event generating hundreds of simultaneous alert workflows could hit this limit. Monitored via CloudWatch.

#### Scale-down removes one task at a time
By design, scale-down removes only one task per cooldown cycle. During a sharp traffic drop (e.g., all riders suddenly go offline), it takes multiple cooldown cycles to reach minimum capacity. This is intentionally conservative — aggressive scale-in risks destabilising services during transient dips.

---

## Future Enhancements (Post-MVP)

### Dedicated Catch-Up Infrastructure (Lambda Architecture)
Currently, live telemetry and catch-up buffer data share the same Telemetry Infrastructure and Hot Storage. For the MVP portfolio project, DynamoDB partition keys natively solve the query isolation problem, and traffic volume is manageable. However, at production scale (millions of data points), burst syncing of historical data could throttle live data ingestion. A future enhancement would implement two dedicated pipelines (Lambda Architecture):
- **Speed Layer**: For live telemetry (low latency, high priority).
- **Batch Layer**: Dedicated SQS queues and Hot Storage tables for catch-up data (high throughput, lower priority). This reduces cost by using cheaper DB write provisioning for delayed data and ensures buffer flushes never impact live crash detection.
