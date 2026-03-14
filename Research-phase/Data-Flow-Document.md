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


