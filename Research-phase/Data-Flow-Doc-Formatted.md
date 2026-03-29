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
[Telemetry Infrastructure] → [SQS Crash Queue] : crash event pointer, helmet ID, timestamp                         : if crash flag found
[Processing Infrastructure] → [SQS Crash Queue] : read crash event pointer                                         : event-driven
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
[Telemetry Infrastructure] → [SQS Crash Queue] : crash event pointer, helmet ID, timestamp                         : on crash flag detected
[Processing Infrastructure] → [SQS Crash Queue] : read crash event pointer                                         : event-driven
```

### Processing Infrastructure Validates Crash Event

```
[Processing Infrastructure] → [Hot Storage] : query recent telemetry history for helmet ID                         : immediately on reading crash event pointer from SQS
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
[Alerting Infrastructure] → [SQS Alert Queue]     : read alert event pointer                                        : event-driven
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
[Telemetry Infrastructure] → [SQS Crash Queue] : crash event pointer, helmet ID, timestamp                         : if crash flag found in chunk
[Processing Infrastructure] → [SQS Crash Queue] : read crash event pointer                                         : event-driven
[Processing Infrastructure] → [Processing Infrastructure] : scan for crash flag in synced data                      : immediately on reading pointer from SQS
```

---

### Case A — Sync Within 24 Hours (Hot Storage Data Available)

```
[Processing Infrastructure] → [Hot Storage] : query recent telemetry for helmet ID                                  : on crash flag detected
[Hot Storage] → [Processing Infrastructure] : recent telemetry history                                              : immediately
[Processing Infrastructure] → [Processing Infrastructure] : validate crash event against telemetry history          : immediately
```

##### Sub-branch — Validated as False Positive

```
[Processing Infrastructure] → [Cold Storage] : false positive log entry, helmet ID, crash timestamp, reason, synced at : on false positive decision
```

> No alert sent.

##### Sub-branch — Validated as Genuine Crash

> Proceed to Retrospective Alert below.

---

### Case B — Sync After 24 Hours (No Hot Storage Data Available)

```
[Processing Infrastructure] → [Hot Storage] : query recent telemetry for helmet ID                                  : on crash flag detected
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
[Telemetry Infrastructure] → [SQS Control Queue] : graceful shutdown message pointer, helmet ID, timestamp          : immediately
[Processing Infrastructure] → [SQS Control Queue] : read graceful shutdown message pointer                          : event-driven
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
[Telemetry Infrastructure] → [SQS Control Queue]             : graceful shutdown message pointer, helmet ID, timestamp : immediately
[Processing Infrastructure] → [SQS Control Queue]            : read graceful shutdown message pointer                  : event-driven
[Processing Infrastructure] → [Hot Storage]                  : query telemetry history for helmet ID                   : immediately on reading pointer from SQS
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
[Telemetry Infrastructure] → [SQS Control Queue] : low battery warning pointer, helmet ID, timestamp               : immediately
[Processing Infrastructure] → [SQS Control Queue] : read low battery warning pointer                               : event-driven
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
[Telemetry Infrastructure] → [SQS Control Queue] : shutdown message pointer, helmet ID, timestamp                   : immediately
[Processing Infrastructure] → [SQS Control Queue] : read shutdown message pointer                                   : event-driven
[Processing Infrastructure] → [Hot Storage] : query last telemetry for helmet ID                                    : immediately on reading pointer from SQS
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
[Telemetry Infrastructure] → [SQS Control Queue] : shutdown message pointer, helmet ID, timestamp                   : immediately
[Processing Infrastructure] → [SQS Control Queue] : read shutdown message pointer                                   : event-driven
[Processing Infrastructure] → [Hot Storage] : query telemetry history for helmet ID                                 : immediately on reading pointer from SQS
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
> | 9G | Processing Infrastructure Failure (cloud layer) | ⬜ Pending |
> | 9H | Alerting Infrastructure Failure (cloud layer) | ⬜ Pending |
> | 9I | Database Failure (cloud layer) | ⬜ Pending |
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
[Telemetry Infrastructure] → [SQS Crash Queue]           : crash event pointer, helmet ID, timestamp                : if crash flag found in chunk
[Processing Infrastructure] → [SQS Crash Queue]          : read crash event pointer                                  : event-driven
[Processing Infrastructure] → [Processing Infrastructure] : scan for crash flag in synced data                      : immediately on reading pointer from SQS
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
[Telemetry Infrastructure] → [SQS Crash Queue]           : crash event pointer, helmet ID, timestamp                : if crash flag found in chunk
[Processing Infrastructure] → [SQS Crash Queue]          : read crash event pointer                                  : event-driven
[Processing Infrastructure] → [Processing Infrastructure] : scan for crash flag in synced data                      : immediately on reading pointer from SQS
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
> **Known limitation:** Real-time crash alerts cannot fire during a Telemetry Infrastructure outage. Telemetry Infrastructure is the service that writes crash pointers to SQS Crash Queue. With it down, no new crash events reach Processing Infrastructure. Any crash that occurs during the outage is captured in the Smartphone buffer and processed retrospectively when Telemetry Infrastructure recovers — same mechanic as Flow 4 Retrospective Alert.
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
[Processing Infrastructure] → [SQS Crash Queue]    : read any pre-failure crash event pointers                      : event-driven, until queue is empty
[Processing Infrastructure] → [SQS Control Queue]  : read any pre-failure control event pointers                    : event-driven, until queue is empty
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
[Telemetry Infrastructure] → [SQS Crash Queue]           : crash event pointer, helmet ID, timestamp                : if crash flag found in chunk
[Processing Infrastructure] → [SQS Crash Queue]          : read crash event pointer                                  : event-driven
[Processing Infrastructure] → [Processing Infrastructure] : scan for crash flag in synced data                      : immediately on reading pointer from SQS
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
> **Known limitation:** Processing Infrastructure is the only service that validates crash events and triggers alerts. With it down, no alerts can fire regardless of what crash events are detected during the outage. All crash event pointers, control message pointers, and LWT messages accumulate in their respective SQS queues unread. All three queues are configured with a 14-day message retention period — independent of the Hot Storage 24-hour retention window. Hot Storage telemetry expires at 24 hours; SQS retains event pointers for 14 days. On recovery, Processing Infrastructure drains all three queues: events from within 24 hours of the crash are processed via Branch A (full telemetry validation); events older than 24 hours are processed via Branch B (retrospective alert to rider — no Hot Storage data available). Events still unprocessed after 14 days expire from SQS with no cold storage record — a 14-day Processing Infrastructure outage is a catastrophic failure beyond the scope of this design. DLQ on each queue catches messages that fail to process after recovery (bug/error scenario during drain) and is not used for outage buffering.
>
> **Telemetry collection during outage:** The telemetry pipeline — Helmet → Smartphone → IoT Core → Telemetry Infrastructure → Hot Storage — has no dependency on Processing Infrastructure. Collection and Hot Storage writes continue normally throughout the outage. Crash event pointers continue to be written to SQS Crash Queue by Telemetry Infrastructure on crash flag detection. LWT messages from IoT Core continue to be written to SQS LWT Queue. They simply accumulate unread.

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
[Telemetry Infrastructure] → [SQS Crash Queue] : crash event pointer, helmet ID, timestamp                         : if crash flag found — pointer accumulates unread
```

> Telemetry collection and Hot Storage writes continue normally. SQS Crash Queue and SQS Control Queue accumulate unread pointers. No alerts can fire during this period.

---

### Control Messages During Outage

> Low battery warnings and shutdown messages are forwarded by Telemetry Infrastructure to SQS Control Queue as normal. Processing Infrastructure cannot read them. No ack is sent back for shutdown messages.
```
[Telemetry Infrastructure] → [SQS Control Queue]  : control message pointer, helmet ID, timestamp                  : on receiving low battery warning or shutdown message — pointer accumulates unread
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
[Processing Infrastructure] → [SQS Control Queue] : read all held control message pointers                     : immediately on recovery
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
[Processing Infrastructure] → [SQS Crash Queue]      : read all held crash event pointers                         : after LWT Queue drained
[Processing Infrastructure] → [Hot Storage]           : query telemetry history for helmet ID                      : on each crash event pointer read
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

> Retrospective alert mechanic runs. Identical to Flow 4 Retrospective Alert. See Flow 4 — Retrospective Alert.

---

#### Branch B — Beyond 24 Hours (No Hot Storage Data Available)
```
[Hot Storage] → [Processing Infrastructure]           : no data found — retention window expired                    : immediately
[Processing Infrastructure] → [SQS Alert Queue]         : cannot validate — alert type — retrospective, helmet ID, crash timestamp, incident location from crash pointer : immediately
```

> Retrospective alert mechanic runs. Identical to Flow 4 Retrospective Alert. See Flow 4 — Retrospective Alert. 

---

## Flow 9H — Alerting Infrastructure Failure (Final)

> **Precondition:** Telemetry Infrastructure, IoT Core, and Processing Infrastructure are all operational. Processing Infrastructure writes confirmed crash event pointers to SQS Alert Queue. Alerting Infrastructure is down and cannot read the queue.
>
> **Known limitation:** No crash alerts can be dispatched to Next of Kin or Emergency Services during the outage. SQS Alert Queue is configured with a 14-day message retention period — all confirmed crash event pointers accumulate unread and are drained on recovery. DLQ catches messages that fail to process after recovery (application-layer bug or error during drain) and is not used for outage buffering.

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

> Processing Infrastructure continues operating normally. Confirmed crash event pointers are written to SQS Alert Queue as normal. Alerting Infrastructure is not reading the queue — pointers accumulate unread. 14-day SQS retention ensures no event pointer is lost during any realistic outage.

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

> The in-progress crash event pointer remains in SQS Alert Queue and is processed on recovery. Alert type determination runs at read time — see Flow 3 — Alerting Infrastructure Alert Type Determination.

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
[Alerting Infrastructure] → [SQS Alert Queue]      : read all held alert event pointers                             : immediately on recovery, FCFS order
```

> Alert type determination runs on each event at read time. See Flow 3 — Alerting Infrastructure Alert Type Determination. Standard events are checked against the standard alert threshold in Parameter Store — events that have sat in the queue beyond the threshold are downgraded to retrospective. All retrospective events show a persistent confirm or cancel notification to the rider. If rider is unreachable — cold storage log, no alert fired.