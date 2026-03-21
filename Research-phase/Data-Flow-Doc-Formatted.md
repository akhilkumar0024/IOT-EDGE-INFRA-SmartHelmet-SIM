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
[Telemetry Infrastructure] → [Smartphone] : sync acknowledgement                                                    : on receiving buffered data
[Smartphone] → [Helmet]                   : sync acknowledgement                                                    : immediately
[Helmet] → [Helmet]                       : clear buffer storage                                                    : on receiving sync acknowledgement
[Telemetry Infrastructure] → [Processing Infrastructure] : buffered telemetry data                                  : on receiving buffered data
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
[Helmet] → [Smartphone]                   : crash event, telemetry payload, helmet ID, timestamp                    : immediately
[Smartphone] → [AWS IoT Core]             : crash event, telemetry payload, helmet ID, timestamp                    : immediately via helmet/{helmet_id}/crash topic
[AWS IoT Core] → [Processing Infrastructure] : crash event, telemetry payload, helmet ID, timestamp                : immediately via IoT Core rules engine
```

### Processing Infrastructure Validates Crash Event

```
[Processing Infrastructure] → [Hot Storage] : query recent telemetry history for helmet ID                         : immediately on crash event received
[Hot Storage] → [Processing Infrastructure] : recent telemetry history                                              : immediately
[Processing Infrastructure] → [Processing Infrastructure] : validate crash event against telemetry history          : immediately
```

---

### Branch A — Validated as False Positive

```
[Processing Infrastructure] → [Processing Infrastructure] : false positive confirmed, no alert to fire              : on validation result
[Processing Infrastructure] → [Helmet HUD] : 5-second override window — "False positive detected"                  : immediately
[Processing Infrastructure] → [Smartphone App] : 5-second override window — "False positive detected"              : immediately
```

#### Sub-branch A1 — Rider Does Nothing (Override Window Expires)

```
[Helmet HUD] → [Rider]                    : dismiss notification                                                    : on 5-second window expiry
[Smartphone App] → [Rider]                : dismiss notification                                                    : on 5-second window expiry
[Processing Infrastructure] → [Cold Storage] : false positive log entry, helmet ID, crash timestamp, reason, no override : immediately
```

> No alert sent.

#### Sub-branch A2 — Rider Overrides (Requests Fresh Countdown)

```
[Rider] → [Helmet HUD or Smartphone App]  : override tap                                                            : within 5-second window
[Processing Infrastructure] → [Processing Infrastructure] : override received, start fresh 30-second countdown      : immediately
```

> Proceed to Alert Countdown below.

---

### Branch B — Validated as Genuine Crash

> Proceed directly to Alert Countdown below.

---

### Alert Countdown

```
[Processing Infrastructure] → [Alerting Infrastructure] : crash confirmed, helmet ID, crash timestamp, incident location : on crash confirmation or rider override
[Alerting Infrastructure] → [Helmet HUD]  : 30-second countdown — "Crash detected — cancel to abort alert"         : immediately
[Alerting Infrastructure] → [Smartphone App] : 30-second countdown — "Crash detected — cancel to abort alert"      : immediately
```

> Cloud owns the countdown. Countdown displayed on both devices simultaneously.
> Rider cancels from either device — only one cancel needed.

#### Sub-branch — Rider Cancels Within Countdown

```
[Rider] → [Helmet HUD or Smartphone App]  : cancel                                                                  : within 30-second window
[Helmet HUD or Smartphone App] → [Alerting Infrastructure] : cancel signal, helmet ID, timestamp                    : immediately
[Alerting Infrastructure] → [Alerting Infrastructure] : stop countdown                                              : immediately
[Alerting Infrastructure] → [Helmet HUD]  : dismiss countdown                                                       : immediately
[Alerting Infrastructure] → [Smartphone App] : dismiss countdown                                                    : immediately
[Alerting Infrastructure] → [Cold Storage] : cancelled alert record, helmet ID, crash timestamp, cancelled by rider : immediately
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
[Telemetry Infrastructure] → [Processing Infrastructure] : synced buffered data                                     : on each acknowledged chunk
[Processing Infrastructure] → [Processing Infrastructure] : scan for crash flag in synced data                      : immediately
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
[Processing Infrastructure] → [Alerting Infrastructure] : crash confirmed, helmet ID, crash timestamp, incident location from buffer, current location from phone : on crash confirmation
[Alerting Infrastructure] → [Smartphone App]            : persistent notification — "Crash detected at [timestamp] — Alert emergency services?"                  : immediately
[Alerting Infrastructure] → [Helmet HUD]                : persistent notification — "Crash detected at [timestamp] — Alert emergency services?"                  : immediately
```

> No countdown. Notification persists until rider explicitly acts.

#### Sub-branch — Rider Cancels

```
[Rider] → [Smartphone App]                : cancel                                                                  : on rider action
[Smartphone App] → [Alerting Infrastructure] : cancel signal, helmet ID, timestamp                                  : immediately
[Alerting Infrastructure] → [Helmet HUD]  : dismiss notification                                                    : immediately
[Alerting Infrastructure] → [Cold Storage] : incident log entry, helmet ID, crash timestamp, incident location, cancelled at, cancelled by rider : immediately
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
[Telemetry Infrastructure] → [Processing Infrastructure] : graceful shutdown message, helmet ID, timestamp          : immediately
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
[Telemetry Infrastructure] → [Processing Infrastructure]     : buffered telemetry payloads, graceful shutdown message, helmet ID, timestamp range : immediately
[Telemetry Infrastructure] → [Smartphone]                    : acknowledgement                                       : on successful receive
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
[Telemetry Infrastructure] → [Processing Infrastructure] : low battery warning, helmet ID, timestamp                : immediately
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
[Telemetry Infrastructure] → [Processing Infrastructure] : shutdown message, last telemetry payload, helmet ID, timestamp : immediately
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
[Processing Infrastructure] → [Telemetry Infrastructure] : shutdown acknowledgement, helmet ID, timestamp           : immediately
[Telemetry Infrastructure] → [Smartphone] : shutdown acknowledgement                                                : immediately
[Smartphone] → [Helmet]                   : shutdown acknowledgement                                                : immediately
[Helmet] → [Helmet]                       : power down on receiving acknowledgement                                 : immediately
[Processing Infrastructure] → [Cold Storage] : false positive log entry, helmet ID, crash timestamp, reason, battery death context : immediately
[Smartphone App] → [Rider]                : "Riding session ended — helmet battery depleted"                        : on shutdown acknowledgement
```

#### Sub-branch — Validated as Genuine Crash

```
[Processing Infrastructure] → [Processing Infrastructure] : crash confirmed, proceed to alert                       : on validation result
[Processing Infrastructure] → [Alerting Infrastructure]  : crash confirmed, helmet ID, crash timestamp, incident location : immediately
[Alerting Infrastructure] → [Smartphone App] : 30-second countdown — "Crash detected — cancel to abort alert"       : immediately
[Alerting Infrastructure] → [Helmet HUD]  : 30-second countdown — "Crash detected — cancel to abort alert"         : immediately
```

> Helmet may power down during countdown — smartphone carries countdown alone if helmet dies.
> Cloud owns the countdown regardless of helmet status.

##### Rider Cancels from Smartphone

```
[Rider] → [Smartphone App]                : cancel                                                                  : within 30-second window
[Smartphone App] → [Alerting Infrastructure] : cancel signal, helmet ID, timestamp                                  : immediately
[Alerting Infrastructure] → [Helmet HUD]  : dismiss notification if still active                                    : immediately
[Alerting Infrastructure] → [Cold Storage] : cancelled alert record, helmet ID, crash timestamp, cancelled by rider, battery death context : immediately
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
[Telemetry Infrastructure] → [Processing Infrastructure] : buffered telemetry, shutdown message, helmet ID, timestamp range : immediately
```

> Processing Infrastructure applies same resolution logic as Flow 6 Sad Path scenarios.

---

## Flow 8 — Unexpected Dropout / LWT

> **Precondition:** Rider is mid-ride. Smartphone disconnects from AWS IoT Core unexpectedly — no warning sent.
> LWT is registered at session startup. IoT Core fires it automatically on unexpected disconnect.

### LWT Fires

```
[AWS IoT Core] → [Processing Infrastructure] : LWT message, helmet ID, last known timestamp                        : on unexpected disconnection detected
[Processing Infrastructure] → [Processing Infrastructure] : start 5-second grace period timer, helmet ID           : immediately on LWT received
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
[Processing Infrastructure] → [Cold Storage] : false positive log entry, helmet ID, crash timestamp, reason, LWT context : immediately
```

> No alert triggered.

#### Sub-branch — Validated as Genuine Crash

```
[Processing Infrastructure] → [Processing Infrastructure] : crash confirmed, proceed to alert                       : on validation result
[Processing Infrastructure] → [Alerting Infrastructure]  : crash confirmed, helmet ID, crash timestamp, incident location : immediately
[Alerting Infrastructure] → [Smartphone App] : 30-second countdown — "Crash detected — cancel to abort alert"       : immediately
[Alerting Infrastructure] → [Helmet HUD]  : 30-second countdown — "Crash detected — cancel to abort alert"         : immediately
```

> Helmet is gone — HUD notification may not be deliverable.
> Smartphone carries the countdown — 30 seconds acts as cancellation window.
> If smartphone or helmet comes back online within countdown — rider can cancel manually.

##### Rider Cancels from Smartphone Within Countdown

```
[Rider] → [Smartphone App]                : cancel                                                                  : within 30-second window
[Smartphone App] → [Alerting Infrastructure] : cancel signal, helmet ID, timestamp                                  : immediately
[Alerting Infrastructure] → [Cold Storage] : cancelled alert record, helmet ID, crash timestamp, cancelled by rider, LWT context : immediately
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