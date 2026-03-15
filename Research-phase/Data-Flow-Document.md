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