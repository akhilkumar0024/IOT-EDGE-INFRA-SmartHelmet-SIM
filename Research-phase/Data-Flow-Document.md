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