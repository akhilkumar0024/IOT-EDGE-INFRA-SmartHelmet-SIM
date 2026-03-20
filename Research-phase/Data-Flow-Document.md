# Startup Sequence

[Rider] → [Helmet] : power on signal : when rider switches helmet on

[Helmet] → [Smartphone] : bluetooth pairing request : immediately after power on
[Smartphone] → [Helmet] : pairing confirmation : on successful bluetooth connection

[Helmet] → [Helmet HUD] : "Connection successful" : on pairing confirmation
[Smartphone App] → [Rider] : "Connection successful" : on pairing confirmation

[Smartphone] → [Telemetry Infrastructure] : connectivity check : after bluetooth pairing confirmed
[Telemetry Infrastructure] → [Smartphone] : connectivity confirmation : on receiving connectivity check
[Smartphone App] → [Rider] : "Cloud connection up" : on connectivity confirmation

[Helmet] → [Helmet] : sensor health check : after bluetooth pairing confirmed

# Health Check — Pass Branch
[Helmet] → [Smartphone] : health check passed, helmet ID, timestamp : on clean health check
[Smartphone] → [Telemetry Infrastructure] : health check passed, helmet ID, timestamp : immediately

# Health Check — Fail Branch
[Helmet] → [Smartphone] : maintenance flag, fault details, helmet ID, timestamp : on failed health check
[Smartphone] → [Telemetry Infrastructure] : maintenance flag, fault details, helmet ID, timestamp : immediately
[Telemetry Infrastructure] → [Cold Storage] : maintenance needed, helmet ID, fault details : on receiving maintenance flag
[Helmet HUD] → [Rider] : "Alert mechanism offline — maintenance required" : on failed health check
[Helmet] → [Helmet] : stop all sensor transmission : after maintenance flag sent

# Buffer Check (only runs on Health Check Pass)
[Helmet] → [Helmet] : check buffer storage : after health check pass

# Buffer Empty Branch — proceed to normal operation
# Buffer Non-Empty Branch
[Helmet] → [Smartphone] : buffered telemetry data, helmet ID, timestamp : on non-empty buffer detected
[Smartphone] → [Telemetry Infrastructure] : buffered telemetry data, helmet ID, timestamp : immediately
[Telemetry Infrastructure] → [Smartphone] : sync acknowledgement : on receiving buffered data
[Smartphone] → [Helmet] : sync acknowledgement : immediately
[Helmet] → [Helmet] : clear buffer storage : on receiving sync acknowledgement
[Telemetry Infrastructure] → [Processing Infrastructure] : buffered telemetry data : on receiving buffered data
[Processing Infrastructure] → [Processing Infrastructure] : scan for alert events in buffered data : immediately

# Normal Telemetry Begins (Happy Path A — after buffer cleared or buffer was empty)
[Helmet Sensors] → [Helmet] : accelerometer, speed, edge result, helmet ID, timestamp : every 1 second
[Helmet] → [Smartphone] : telemetry payload, helmet ID, timestamp : every 1 second
[Smartphone] → [Telemetry Infrastructure] : JSON array of 10 telemetry payloads + GPS + user ID + batch timestamp : every 10 seconds
[Telemetry Infrastructure] → [Hot Storage] : batch payload, batch timestamp : on every receive



# Startup Sequence — Sad Path 1 : Bluetooth Pairing Fails

[Helmet] → [Helmet HUD] : "Connecting to smartphone, attempt 1 of 5" : on each retry
[Helmet] → [Helmet] : retry bluetooth pairing : up to 5 attempts per poweron
[Helmet] → [Helmet] : increment local retry counter : on each failed attempt

# After 5 failed attempts
[Helmet HUD] → [Rider] : "Unable to connect to smartphone — telemetry and alert system not operational" : after 5th failed attempt
[Helmet HUD] → [Rider] : "Please visit maintenance shop" : after 5th failed attempt
[Helmet] → [Helmet] : retain buffer storage, do not clear : at all times until sync confirmation received

# When bluetooth eventually succeeds (future poweron)
[Helmet] → [Smartphone] : buffered telemetry data + cumulative local retry count + helmet ID + timestamp : on successful pairing
[Smartphone] → [Telemetry Infrastructure] : buffered telemetry data + cumulative retry count + helmet ID + timestamp : immediately
[Telemetry Infrastructure] → [Cold Storage] : cumulative retry count update, helmet ID, timestamp : on receive
[Telemetry Infrastructure] → [Smartphone] : sync acknowledgement : on successful storage
[Smartphone] → [Helmet] : sync acknowledgement : immediately
[Helmet] → [Helmet] : clear buffer storage : on receiving sync acknowledgement

# Local counter threshold warning (50 cumulative retries)
[Helmet] → [Helmet HUD] : "Persistent connection issues — maintenance recommended" : when local counter crosses 50

# Fleet Manager reset action
[Fleet Manager] → [Fleet Management System] : reset helmet counter request, helmet ID : when maintenance is completed
[Fleet Management System] → [Telemetry Infrastructure] : counter reset request, helmet ID, timestamp : immediately
[Telemetry Infrastructure] → [Helmet] : reset local retry counter command : via smartphone on next successful sync
[Helmet] → [Helmet] : reset local counter : on receiving reset command
[Telemetry Infrastructure] → [Cold Storage] : counter reset event logged, helmet ID, timestamp, reset authorised by Fleet Manager : immediately


# Startup Sequence — Sad Path 2 Sub-scenario A : Smartphone has no internet

[Smartphone] → [Helmet] : no internet connectivity detected : on connectivity check
[Helmet HUD] → [Rider] : "No internet connectivity — telemetry and alert system not operational" : immediately
[Smartphone App] → [Rider] : "No internet connectivity — alert system not operational" : immediately

# Helmet continues collecting and forwarding data to smartphone
[Helmet Sensors] → [Helmet] : accelerometer, speed, edge result, helmet ID, timestamp : every 1 second
[Helmet] → [Smartphone] : telemetry payload, helmet ID, timestamp : every 1 second
[Smartphone] → [Smartphone Local Storage] : telemetry payload : every 1 second, until internet restores

# On internet restore
[Smartphone] → [Helmet HUD] : "Internet connectivity restored" : on connectivity restore
[Smartphone App] → [Rider] : "Internet connectivity restored — telemetry and alert system operational" : immediately

# Backlog flush via catch-up channel
[Smartphone] → [Telemetry Infrastructure — Catch-up Channel] : 50 second chunk of backlog data, chunk sequence number, helmet ID, timestamp range : starting from oldest unacknowledged chunk
[Telemetry Infrastructure] → [Smartphone] : chunk acknowledgement, chunk sequence number : on receiving full 50 second chunk
[Smartphone] → [Telemetry Infrastructure — Catch-up Channel] : next 50 second chunk : on receiving acknowledgement of previous chunk

# Partial chunk or no acknowledgement
[Smartphone] → [Telemetry Infrastructure — Catch-up Channel] : resend same chunk in full : if no acknowledgement received within timeout

# Duplicate chunk detection
[Telemetry Infrastructure] → [Telemetry Infrastructure] : check timestamp range against existing Hot Storage entries : on every chunk receive
[Telemetry Infrastructure] → [Telemetry Infrastructure] : discard duplicate chunk : if timestamp range already exists in Hot Storage
[Telemetry Infrastructure] → [Smartphone] : acknowledgement : on duplicate detected, so smartphone moves to next chunk

# Live data resumes normal flow alongside catch-up channel
[Smartphone] → [Telemetry Infrastructure — Live Channel] : JSON array of 10 telemetry payloads + GPS + user ID + batch timestamp : every 10 seconds
[Telemetry Infrastructure] → [Hot Storage] : live batch payload : on every receive
[Telemetry Infrastructure] → [Hot Storage] : acknowledged chunk payload : on each confirmed chunk

# Backlog fully flushed
[Smartphone] → [Smartphone] : all chunks acknowledged, backlog fully flushed : after final chunk acknowledgement received
[Smartphone] → [Smartphone Local Storage] : clear backlog data : immediately after full flush confirmed


# Startup Sequence — Sad Path 2 Sub-scenario B : Telemetry Infrastructure unreachable

[Smartphone] → [Telemetry Infrastructure] : connectivity check : after bluetooth pairing confirmed
[Telemetry Infrastructure] → [Smartphone] : no response : —

[Smartphone App] → [Rider] : "Telemetry Infrastructure unreachable — not a device issue, please be patient" : immediately
[Helmet HUD] → [Rider] : "Telemetry Infrastructure unreachable — alert and telemetry systems not operational" : immediately

# Infrastructure side — outage detection
[Monitoring Infrastructure] → [Telemetry Infrastructure] : health check : at regular intervals
[Telemetry Infrastructure] → [Monitoring Infrastructure] : no response : —
[Monitoring Infrastructure] → [Infrastructure Engineer] : outage alert, telemetry infrastructure unreachable, timestamp : after health check failure threshold crossed

# Helmet and smartphone behaviour during outage — same as Sub-scenario A
[Helmet Sensors] → [Helmet] : accelerometer, speed, edge result, helmet ID, timestamp : every 1 second
[Helmet] → [Smartphone] : telemetry payload, helmet ID, timestamp : every 1 second
[Smartphone] → [Smartphone Local Storage] : telemetry payload : every 1 second until infra restores

# On Telemetry Infrastructure restore
[Monitoring Infrastructure] → [Telemetry Infrastructure] : health check : at regular intervals
[Telemetry Infrastructure] → [Monitoring Infrastructure] : health check passed : on recovery
[Monitoring Infrastructure] → [Infrastructure Engineer] : telemetry infrastructure restored, timestamp : immediately
[Smartphone] → [Helmet HUD] : "Telemetry Infrastructure restored" : on successful connectivity check
[Smartphone App] → [Rider] : "Telemetry Infrastructure restored — telemetry and alert systems operational" : immediately

# Backlog flush and clear — identical to Sub-scenario A
[Smartphone] → [Telemetry Infrastructure — Catch-up Channel] : 50 second chunk of backlog data, chunk sequence number, helmet ID, timestamp range : starting from oldest unacknowledged chunk
[Telemetry Infrastructure] → [Smartphone] : chunk acknowledgement, chunk sequence number : on receiving full 50 second chunk
[Smartphone] → [Telemetry Infrastructure — Catch-up Channel] : next 50 second chunk : on receiving acknowledgement of previous chunk
[Smartphone] → [Telemetry Infrastructure — Catch-up Channel] : resend same chunk in full : if no acknowledgement received within timeout
[Telemetry Infrastructure] → [Telemetry Infrastructure] : check timestamp range against existing Hot Storage entries : on every chunk receive
[Telemetry Infrastructure] → [Telemetry Infrastructure] : discard duplicate chunk : if timestamp range already exists in Hot Storage
[Telemetry Infrastructure] → [Smartphone] : acknowledgement : on duplicate detected
[Smartphone] → [Telemetry Infrastructure — Live Channel] : JSON array of 10 telemetry payloads + GPS + user ID + batch timestamp : every 10 seconds
[Telemetry Infrastructure] → [Hot Storage] : live batch payload : on every receive
[Telemetry Infrastructure] → [Hot Storage] : acknowledged chunk payload : on each confirmed chunk
[Smartphone] → [Smartphone] : all chunks acknowledged, backlog fully flushed : after final chunk acknowledgement received
[Smartphone] → [Smartphone Local Storage] : clear backlog data : immediately after full flush confirmed


# Startup Sequence — Sad Path 2 Sub-scenario C : Buffer sync fails on forward to Telemetry Infrastructure

# Context: Helmet has buffered data → successfully sent to smartphone via bluetooth
# Smartphone has internet, Telemetry Infrastructure is up, but forward fails
# Helmet buffer is NOT cleared until full ack chain completes
# TTL for unconfirmed chunks = 24 hours (stored in Parameter Store)

# Rider status during sync attempt
[Smartphone App] → [Rider] : "Data sync in progress" : on receiving buffered data from helmet
[Helmet HUD] → [Rider] : "Data sync in progress" : on receiving buffered data from helmet
[Smartphone App] → [Rider] : "Alert and telemetry systems operational" : on connectivity confirmed
[Helmet HUD] → [Rider] : "Alert and telemetry systems operational" : on connectivity confirmed

# Smartphone forwards buffer to Telemetry Infrastructure via catch-up channel
[Smartphone] → [Telemetry Infrastructure — Catch-up Channel] : 50 second chunk of backlog data, chunk sequence number, helmet ID, timestamp range : starting from oldest chunk

# -----------------------------------------------------------------------
# Case 1 — DB Full
# -----------------------------------------------------------------------

# Infra rejects with storage full error
[Telemetry Infrastructure] → [Smartphone] : storage full error, chunk sequence number : on write rejection

# Rider informed
[Smartphone App] → [Rider] : "Buffer sync paused — cloud storage full, retrying when resolved" : immediately
[Helmet HUD] → [Rider] : "Buffer sync paused — cloud storage issue, alert system still operational" : immediately

# Monitoring infra detects storage threshold breach
[Monitoring Infrastructure] → [Telemetry Infrastructure] : storage utilisation check : at regular intervals
[Monitoring Infrastructure] → [Infrastructure Engineer] : storage full alert, helmet ID, timestamp : when threshold breached

# Smartphone holds chunk locally until infra recovers
[Smartphone] → [Smartphone Local Storage] : retain chunk, mark as undelivered : immediately on storage full error

# Infrastructure Engineer provisions storage
[Infrastructure Engineer] → [Telemetry Infrastructure] : provision additional storage : on receiving alert

# On storage restored — resume catch-up channel flow
[Smartphone] → [Telemetry Infrastructure — Catch-up Channel] : retry undelivered chunk, chunk sequence number, helmet ID, timestamp range : on storage restored
[Telemetry Infrastructure] → [Smartphone] : chunk acknowledgement, chunk sequence number : on successful write
[Smartphone] → [Helmet] : sync acknowledgement for cleared chunk : immediately
[Helmet] → [Helmet] : clear that chunk from buffer storage : on receiving acknowledgement
[Smartphone] → [Smartphone Local Storage] : clear that chunk : immediately after helmet confirms clear
[Telemetry Infrastructure] → [Hot Storage] : telemetry data from acknowledged chunk : on each confirmed chunk write


# -----------------------------------------------------------------------
# Case 2 — Corrupt Data
# -----------------------------------------------------------------------

# Infra validates payload before writing — rejects with bad payload error
[Telemetry Infrastructure] → [Smartphone] : bad payload error, chunk sequence number, timestamp range : on validation failure

# Smartphone requests helmet to resend that chunk
[Smartphone] → [Helmet] : resend chunk request, chunk sequence number, timestamp range : immediately on bad payload error

# Helmet resends chunk from buffer (buffer still intact)
[Helmet] → [Smartphone] : buffered chunk data, chunk sequence number, helmet ID, timestamp : on resend request

# Smartphone retries forward to Telemetry Infrastructure — attempt 2
[Smartphone] → [Telemetry Infrastructure — Catch-up Channel] : resent chunk data, chunk sequence number, helmet ID, timestamp range : immediately

# Resend accepted branch
[Telemetry Infrastructure] → [Smartphone] : chunk acknowledgement, chunk sequence number : on successful write
[Smartphone] → [Helmet] : sync acknowledgement for that chunk : immediately
[Helmet] → [Helmet] : clear that chunk from buffer storage : on receiving acknowledgement
[Smartphone] → [Smartphone Local Storage] : clear that chunk : immediately after helmet confirms clear
[Telemetry Infrastructure] → [Hot Storage] : telemetry data from acknowledged chunk : on each confirmed chunk write

# Resend rejected branch — discard and log
[Telemetry Infrastructure] → [Smartphone] : bad payload error, chunk sequence number, timestamp range : on second validation failure
[Telemetry Infrastructure] → [Cold Storage] : corrupt chunk log entry, helmet ID, chunk timestamp range, rejection reason, resend attempted true, resend outcome failed, logged at : immediately
[Smartphone] → [Helmet] : discard chunk command, chunk sequence number, timestamp range : immediately
[Helmet] → [Helmet] : clear that chunk from buffer storage : on receiving discard command
[Smartphone] → [Smartphone Local Storage] : clear that chunk : immediately after helmet confirms clear

# Monitoring infra checks corrupt rejection count for this helmet
[Monitoring Infrastructure] → [Cold Storage] : query corrupt rejection count for helmet ID : at regular intervals
[Monitoring Infrastructure] → [Infrastructure Engineer] : corrupt data threshold exceeded alert, helmet ID, timestamp : if count exceeds threshold in Parameter Store


# -----------------------------------------------------------------------
# Case 3 — Ack Lost (resolved by idempotency + TTL)
# -----------------------------------------------------------------------

# Infra stored the chunk successfully but ack never reached smartphone
[Smartphone] → [Smartphone] : ack timeout, no acknowledgement received : after 30 seconds
[Smartphone] → [Telemetry Infrastructure — Catch-up Channel] : resend same chunk, chunk sequence number, helmet ID, timestamp range : on timeout (attempt 2)

# Infra detects duplicate via timestamp range — discards, sends ack
[Telemetry Infrastructure] → [Telemetry Infrastructure] : check timestamp range against existing Hot Storage entries : on every chunk receive
[Telemetry Infrastructure] → [Telemetry Infrastructure] : discard duplicate chunk : timestamp range already exists in Hot Storage
[Telemetry Infrastructure] → [Smartphone] : chunk acknowledgement, chunk sequence number : on duplicate detected

# If ack lost again — attempt 3
[Smartphone] → [Smartphone] : ack timeout, no acknowledgement received : after 30 seconds
[Smartphone] → [Telemetry Infrastructure — Catch-up Channel] : resend same chunk, chunk sequence number, helmet ID, timestamp range : on timeout (attempt 3)
[Telemetry Infrastructure] → [Telemetry Infrastructure] : discard duplicate chunk : timestamp range already exists in Hot Storage
[Telemetry Infrastructure] → [Smartphone] : chunk acknowledgement, chunk sequence number : on duplicate detected

# If all 3 attempts fail — smartphone connectivity issue suspected
# Data is safe in infra — problem is ack not reaching smartphone
[Smartphone] → [Smartphone] : ack timeout after 3 attempts : —
[Smartphone App] → [Rider] : "Sync confirmation not received — possible connectivity issue on device" : immediately
[Helmet HUD] → [Rider] : "Sync confirmation not received — alert system status uncertain" : immediately

# Smartphone holds chunk locally — does not clear helmet buffer
[Smartphone] → [Smartphone Local Storage] : retain chunk, mark as unconfirmed, record chunk creation timestamp : immediately

# Monitoring infra detects repeated duplicate submissions as anomaly
[Monitoring Infrastructure] → [Cold Storage] : query duplicate submission count for helmet ID : at regular intervals
[Monitoring Infrastructure] → [Infrastructure Engineer] : repeated duplicate submissions detected, helmet ID, timestamp : if count exceeds threshold in Parameter Store

# On next connectivity restore — smartphone retries automatically
# Infra detects duplicate again via timestamp range — acks cleanly
[Smartphone] → [Telemetry Infrastructure — Catch-up Channel] : resend chunk, chunk sequence number, helmet ID, timestamp range : on connectivity restore
[Telemetry Infrastructure] → [Telemetry Infrastructure] : discard duplicate chunk : timestamp range already exists in Hot Storage
[Telemetry Infrastructure] → [Smartphone] : chunk acknowledgement, chunk sequence number : on duplicate detected
[Smartphone] → [Helmet] : sync acknowledgement for that chunk : immediately
[Helmet] → [Helmet] : clear that chunk from buffer storage : on receiving acknowledgement
[Smartphone] → [Smartphone Local Storage] : clear that chunk : immediately after helmet confirms clear

# TTL expiry — chunk held unconfirmed beyond 24 hours (TTL value in Parameter Store)
[Smartphone] → [Smartphone] : check unconfirmed chunk age against TTL : at regular intervals
[Smartphone] → [Smartphone] : TTL expired for chunk : when chunk creation timestamp exceeds 24 hours

# Forced discard
[Smartphone] → [Helmet] : discard chunk command, chunk sequence number, timestamp range : immediately on TTL expiry
[Helmet] → [Helmet] : clear that chunk from buffer storage : on receiving discard command
[Smartphone] → [Smartphone Local Storage] : clear that chunk : immediately after helmet confirms clear

# Log and alert
[Telemetry Infrastructure] → [Cold Storage] : TTL expiry log entry, helmet ID, chunk timestamp range, chunk creation timestamp, discarded at, reason — ack never confirmed : immediately
[Monitoring Infrastructure] → [Infrastructure Engineer] : TTL expiry alert, helmet ID, chunk timestamp range, timestamp : immediately on log entry written


# Phone Dead During Crash — Precondition
# Rider is mid-ride
# Smartphone is completely off — not low battery, fully dead
# Helmet is active, sensors running normally
# No bluetooth connection between helmet and smartphone

# Crash detected by helmet edge processing
[Helmet Sensors] → [Helmet] : accelerometer spike, speed data, edge result flagged as crash, helmet ID, timestamp : on crash detection
[Helmet] → [Helmet] : check for smartphone connection : immediately on crash detection
[Helmet] → [Helmet] : no smartphone connection detected : immediately

# No cloud path — helmet buffers and waits
[Helmet] → [Helmet] : store crash event + surrounding telemetry in buffer : immediately
[Helmet HUD] → [Rider] : "Alert system unavailable — event data stored" : immediately
# No 30 second countdown
# No alert window
# No action required from rider

# Helmet continues operating
[Helmet Sensors] → [Helmet] : accelerometer, speed, edge result, helmet ID, timestamp : every 1 second
[Helmet] → [Helmet] : store all telemetry in buffer : every 1 second
# No cloud path — buffer only

# Phone revives — normal startup sequence runs
[Smartphone] → [Helmet] : bluetooth pairing request : on smartphone power on
[Helmet] → [Smartphone] : pairing confirmation : on successful bluetooth connection
[Smartphone] → [Telemetry Infrastructure] : connectivity check : after bluetooth pairing confirmed
[Telemetry Infrastructure] → [Smartphone] : connectivity confirmation : on receiving connectivity check

# Catch-up sync initiates automatically — no special trigger
# Both devices check local storage for unsynced data
# Buffer contains pre-crash telemetry + crash event + post-crash telemetry
# All treated as regular buffered data — crash flag is just another datapoint

[Helmet] → [Smartphone] : buffered telemetry data including crash event, helmet ID, timestamp range : on successful pairing
[Smartphone] → [Telemetry Infrastructure — Catch-up Channel] : 50 second chunk of backlog data, chunk sequence number, helmet ID, timestamp range : starting from oldest unacknowledged chunk
[Telemetry Infrastructure] → [Smartphone] : chunk acknowledgement, chunk sequence number : on receiving full 50 second chunk
[Smartphone] → [Telemetry Infrastructure — Catch-up Channel] : next 50 second chunk : on receiving acknowledgement of previous chunk

# Telemetry Infrastructure forwards to Processing Infrastructure
[Telemetry Infrastructure] → [Processing Infrastructure] : synced buffered data : on each acknowledged chunk
[Processing Infrastructure] → [Processing Infrastructure] : scan for crash flag in synced data : immediately

# Processing Infrastructure validates — two cases

# -----------------------------------------------------------------------
# Case A — Sync within 24 hours (hot storage data available)
# -----------------------------------------------------------------------

[Processing Infrastructure] → [Hot Storage] : query recent telemetry for helmet ID : on crash flag detected
[Hot Storage] → [Processing Infrastructure] : recent telemetry history : immediately
[Processing Infrastructure] → [Processing Infrastructure] : validate crash event against telemetry history : immediately

# Validated as crash — proceed to retrospective alert
# Validated as false positive branch
[Processing Infrastructure] → [Cold Storage] : false positive log entry, helmet ID, crash timestamp, reason, synced at : on false positive decision
# No alert sent

# -----------------------------------------------------------------------
# Case B — Sync after 24 hours (no hot storage data available)
# -----------------------------------------------------------------------

[Processing Infrastructure] → [Hot Storage] : query recent telemetry for helmet ID : on crash flag detected
[Hot Storage] → [Processing Infrastructure] : no data found : immediately
[Processing Infrastructure] → [Processing Infrastructure] : validate crash event against buffered data only, apply lower confidence threshold, lean toward alert : immediately

# -----------------------------------------------------------------------
# Retrospective alert — runs after Case A validated or Case B confirmed
# -----------------------------------------------------------------------

[Processing Infrastructure] → [Alerting Infrastructure] : crash confirmed, helmet ID, crash timestamp, incident location from buffer, current location from phone : on crash confirmation
[Alerting Infrastructure] → [Smartphone App] : persistent notification — "Crash detected at [timestamp] — Alert emergency services?" : immediately
[Alerting Infrastructure] → [Helmet HUD] : persistent notification — "Crash detected at [timestamp] — Alert emergency services?" : immediately
# No countdown — notification persists until rider explicitly acts

# Rider cancels branch
[Rider] → [Smartphone App] : cancel : on rider action
[Smartphone App] → [Alerting Infrastructure] : cancel signal, helmet ID, timestamp : immediately
[Alerting Infrastructure] → [Helmet HUD] : dismiss notification : immediately
[Alerting Infrastructure] → [Cold Storage] : incident log entry, helmet ID, crash timestamp, incident location, cancelled at, cancelled by rider : immediately
# No alert sent to Next of Kin or Emergency Services

# Rider confirms or does not respond branch
[Alerting Infrastructure] → [Next of Kin] : crash alert, incident location, current location, incident timestamp : immediately on confirm or no response
[Alerting Infrastructure] → [Emergency Services] : crash alert, incident location, current location, incident timestamp, speed at time of crash, next of kin contact : immediately, independent of Next of Kin channel
# Retries on each channel do not block the other

# Delivery success branch
[Next of Kin] → [Alerting Infrastructure] : acknowledgement : on receiving alert
[Emergency Services] → [Alerting Infrastructure] : acknowledgement : on receiving alert
[Alerting Infrastructure] → [Cold Storage] : delivery success log, helmet ID, channel, timestamp : on each acknowledgement

# Delivery failure branch
[Alerting Infrastructure] → [Alerting Infrastructure] : retry alert, channel : on no acknowledgement received
[Alerting Infrastructure] → [Cold Storage] : delivery failure log, helmet ID, channel, attempt number, timestamp : on each failed attempt

# Storage — written regardless of outcome
[Alerting Infrastructure] → [Cold Storage] : incident record, helmet ID, crash timestamp, incident location, current location at alert time, confirmation or cancellation, delivery outcome per channel : immediately on resolution

# Graceful Shutdown — Happy Path
# Rider switches helmet off
# Smartphone has internet, Telemetry Infrastructure is reachable

[Rider] → [Helmet] : power off signal : when rider switches helmet off

# Helmet flushes remaining unsent telemetry to smartphone before shutdown
[Helmet] → [Smartphone] : remaining unsent telemetry payloads, helmet ID, timestamp : immediately on power off signal
[Smartphone] → [Telemetry Infrastructure — Live Channel] : remaining telemetry payloads, helmet ID, timestamp : immediately
[Telemetry Infrastructure] → [Hot Storage] : remaining telemetry payloads : on receive
[Telemetry Infrastructure] → [Smartphone] : telemetry acknowledgement : on successful write

# Helmet sends graceful shutdown message
[Helmet] → [Smartphone] : graceful shutdown message, helmet ID, timestamp : after remaining telemetry flushed
[Smartphone] → [Telemetry Infrastructure] : graceful shutdown message, helmet ID, timestamp : immediately
[Telemetry Infrastructure] → [Processing Infrastructure] : graceful shutdown message, helmet ID, timestamp : immediately
[Processing Infrastructure] → [Processing Infrastructure] : mark helmet as gracefully offline : immediately
[Processing Infrastructure] → [Telemetry Infrastructure] : shutdown acknowledgement, helmet ID, timestamp : immediately
[Telemetry Infrastructure] → [Smartphone] : shutdown acknowledgement, helmet ID, timestamp : immediately
[Smartphone] → [Helmet] : shutdown acknowledgement : immediately
[Helmet] → [Helmet] : power down : on receiving shutdown acknowledgement

# Smartphone notifies rider
[Smartphone App] → [Rider] : "Riding session ended — helmet is now offline" : on shutdown acknowledgement received

# Hot storage retention window starts from last telemetry batch timestamp
[Processing Infrastructure] → [Hot Storage] : start 24 hour retention window, helmet ID, last telemetry batch timestamp : immediately on graceful shutdown marked
# No cold storage write — graceful shutdown is a normal event, nothing to record

# Nothing written to cold storage
# No alert triggered


# Graceful Shutdown — Sad Path
# Rider switches helmet off
# Shutdown acknowledgement not received within 10 seconds
# Helmet powers down regardless — buffer retained

[Rider] → [Helmet] : power off signal : when rider switches helmet off
[Helmet] → [Smartphone] : remaining unsent telemetry payloads, helmet ID, timestamp : immediately on power off signal
[Helmet] → [Smartphone] : graceful shutdown message, helmet ID, timestamp : after remaining telemetry flushed
[Helmet] → [Helmet] : start 10 second acknowledgement timer : immediately after shutdown message sent
[Helmet] → [Helmet] : no acknowledgement received within 10 seconds : on timer expiry
[Helmet] → [Helmet] : power down, retain buffer storage : on timer expiry
# Helmet powers down without cloud acknowledgement
# Buffer retained — data not lost

# From cloud perspective — no shutdown message received yet
# LWT fires automatically — cloud treats as Type 3 unexpected dropout
# Type 3 flow runs independently — not modified here

# Smartphone retains buffered telemetry and graceful shutdown message in local storage
[Smartphone] → [Smartphone Local Storage] : buffered telemetry payloads, graceful shutdown message, helmet ID, timestamp : immediately on helmet power down

# On connectivity restore — smartphone syncs buffer including graceful shutdown message
[Smartphone] → [Telemetry Infrastructure — Catch-up Channel] : buffered telemetry payloads, graceful shutdown message, helmet ID, timestamp range : on connectivity restore
[Telemetry Infrastructure] → [Processing Infrastructure] : buffered telemetry payloads, graceful shutdown message, helmet ID, timestamp range : immediately
[Telemetry Infrastructure] → [Smartphone] : acknowledgement : on successful receive

# Processing Infrastructure checks where Type 3 process currently stands
[Processing Infrastructure] → [Processing Infrastructure] : check Type 3 process status for helmet ID : on receiving graceful shutdown message

# -----------------------------------------------------------------------
# Scenario 1 — Type 3 process identified false positive, no alert fired
# -----------------------------------------------------------------------

[Processing Infrastructure] → [Processing Infrastructure] : graceful shutdown confirmed, false positive validated, no alert was fired : on status check
[Telemetry Infrastructure] → [Hot Storage] : buffered telemetry payloads : on receive
# Hot storage retention window — 24 hours from last telemetry batch timestamp
# False alert event log already written to cold storage during Type 3 process — nothing new added
# No additional cold storage write on graceful shutdown confirmation
[Smartphone App] → [Rider] : "Riding session ended — helmet is now offline" : on graceful shutdown confirmed


# -----------------------------------------------------------------------
# Scenario 2A — Alert countdown still active when buffered data arrives
# -----------------------------------------------------------------------

[Processing Infrastructure] → [Processing Infrastructure] : graceful shutdown message received, alert countdown still active : on status check
[Processing Infrastructure] → [Alerting Infrastructure] : cancel alert countdown, helmet ID, timestamp, reason — graceful shutdown confirmed : immediately
[Alerting Infrastructure] → [Alerting Infrastructure] : cancel alert countdown : immediately
[Alerting Infrastructure] → [Smartphone App] : "Alert cancelled — graceful shutdown confirmed" : immediately
# Helmet is powered down — no HUD notification possible
[Smartphone App] → [Rider] : "Alert was triggered but has been cancelled — your session ended safely" : immediately

# Rider given option to send alert manually since helmet is offline
[Smartphone App] → [Rider] : "Do you want to alert emergency services anyway?" : immediately
# Rider confirms branch
[Rider] → [Smartphone App] : confirm : on rider action
[Smartphone App] → [Alerting Infrastructure] : manual alert request, helmet ID, timestamp, initiated by rider via smartphone : immediately
[Alerting Infrastructure] → [Next of Kin] : crash alert, incident location, current location, incident timestamp : immediately
[Alerting Infrastructure] → [Emergency Services] : crash alert, incident location, current location, incident timestamp, next of kin contact : immediately, independent of Next of Kin channel
[Alerting Infrastructure] → [Cold Storage] : manual alert record, helmet ID, timestamp, initiated by rider, channel delivery outcomes : on resolution

# Rider cancels branch
[Rider] → [Smartphone App] : cancel : on rider action
[Alerting Infrastructure] → [Cold Storage] : alert cancelled record, helmet ID, timestamp, cancelled by rider after graceful shutdown confirmed : immediately

# Telemetry written to hot storage regardless of rider choice
[Telemetry Infrastructure] → [Hot Storage] : buffered telemetry payloads : on receive


# -----------------------------------------------------------------------
# Scenario 2B — Alert already fired before buffered data arrives
# -----------------------------------------------------------------------

[Processing Infrastructure] → [Processing Infrastructure] : graceful shutdown message received, alert already fired : on status check
[Alerting Infrastructure] → [Smartphone App] : "Alert has already been sent to Next of Kin and Emergency Services" : immediately
[Smartphone App] → [Rider] : "Next of Kin and Emergency Services have been alerted — do you want to notify them the rider is safe?" : immediately

# Rider confirms — notify that rider is safe
[Rider] → [Smartphone App] : confirm : on rider action
[Smartphone App] → [Alerting Infrastructure] : rider safe notification request, helmet ID, timestamp, initiated by rider : immediately
[Alerting Infrastructure] → [Next of Kin] : rider safe notification — previous alert was a false positive : immediately
[Alerting Infrastructure] → [Emergency Services] : rider safe notification — previous alert was a false positive : immediately, independent of Next of Kin channel
[Alerting Infrastructure] → [Cold Storage] : rider safe notification record, helmet ID, timestamp, rider choice confirmed, channel delivery outcomes : immediately

# Rider declines — does not notify
[Rider] → [Smartphone App] : cancel : on rider action
[Alerting Infrastructure] → [Cold Storage] : rider safe notification declined, helmet ID, timestamp, rider choice declined : immediately

# Telemetry written to hot storage regardless of rider choice
[Telemetry Infrastructure] → [Hot Storage] : buffered telemetry payloads : on receive

