# Smart Helmet IoT Edge Infrastructure — Actors List
**Project:** IOT-EDGE-INFRA-SmartHelmet-SIM  
**Phase:** Research  
**Status:** Conflicts resolved — ready for Data Flow phase

---

## Conflict Resolutions (recorded for reference)

| Conflict | Decision |
|---|---|
| Helmet vs Smartphone as cloud comm owner | Smartphone is primary relay. Helmet talks directly to cloud in simulation only. Direct helmet-to-cloud comms = future hardware scope. |
| 30-second cancel window ownership | Cancel works from either Helmet HUD or Smartphone independently. Only one cancel action needed regardless of which device triggers it. If Smartphone is dead, alert never reached cloud — Helmet suppresses locally. No cloud-side cancel needed in that scenario. |
| Firmware update ownership | Infrastructure Engineer owns infra pipeline. Fleet Manager owns firmware pipeline. Two separate pipelines, no overlap. |
| False positive filtering ownership | Processing Infra = decision layer (filters false positives). Alerting Infra = delivery layer (deduplication, acknowledgement tracking). No overlap. |
| Shutdown type classification | Three distinct shutdown types: (1) Graceful — rider switches off, helmet sends deliberate shutdown message, cloud marks offline, no alert. (2) Battery death — helmet sends low battery warning before dying, cloud uses last telemetry to classify normal fade vs crash, countdown triggered only if last telemetry shows abnormal acceleration. (3) Unexpected dropout — no warning, LWT fires, cloud treats as suspicious, checks last telemetry, may trigger alert countdown. |
| Retrospective alert after phone revival | If phone was dead during crash, helmet buffers crash event locally. When phone comes back online, helmet syncs buffer to cloud. Smartphone app notifies rider with option to alert emergency services. Rider decides — confirms or cancels. Either way incident is written to cold storage DB. Alert payload includes both incident location (from buffer at time of crash) and current location (from phone at time of alert) plus incident timestamp. |
| Phone low battery behaviour | Smartphone app sends low battery warning to cloud before dying. Cloud marks smartphone as expected offline. No alert triggered. Helmet continues riding but has no cloud comms path — stores telemetry locally. Cloud marks helmet as comms suspended — phone offline. Alert feature unavailable until phone comes back online. |

---

## Actors

---

### Helmet

> **Simulation note:** In simulation, Helmet is Script 1 — generates sensor data and edge processing result, sends to Smartphone Script 2 via local socket or queue. Script 2 aggregates and forwards to cloud. Helmet never communicates directly with cloud in either real hardware or simulation.

**Needs**
- Sufficient power to operate sensors continuously during a ride
- Compute capacity to run edge processing (crash detection locally)
- Stable Bluetooth connection to Smartphone for data relay
- Ability to receive firmware updates from cloud via Fleet Manager pipeline
- Local storage buffer for telemetry data during connectivity loss
- Built-in sensor health check to detect and flag sensor failure

**Fears**
- Sensor failure or corruption producing false telemetry data
- False crash alert sent without rider acknowledgement
- Rider ignoring repeated false positive alerts (alert fatigue)
- Failing to connect to Smartphone — single point of failure for cloud comms (accepted for now, backup comms = future scope)
- User without a Smartphone (edge case — must have fallback consideration in future)
- Malicious actor hacking, tampering, or simulating a crash event
- Failure to transmit telemetry to Telemetry Infrastructure
- Edge processing unit damaged in a crash producing corrupted events
- Battery dying mid-ride with no warning sent — cloud cannot distinguish from crash

**Triggers**
- Rider powers on helmet and initiates Bluetooth pairing with Smartphone
- Sensor threshold exceeded — potential crash event detected by edge processing
- Connectivity loss to Smartphone detected
- Sensor health check failure detected
- Firmware update received via Fleet Manager pipeline
- LWT triggered by unexpected disconnection from broker (Type 3 shutdown — no warning)
- Graceful shutdown initiated by rider switching helmet off (Type 1 shutdown)
- Low battery threshold reached — sends warning before powering down (Type 2 shutdown)
- Helmet HUD cancel button pressed during 30-second alert window
- Smartphone comes back online — helmet syncs locally buffered telemetry to cloud

---

### Rider

**Needs**
- Helmet that alerts emergency services automatically in a crash
- HUD display showing speed and connectivity health (green indicator)
- 30-second cancel window after crash detection before alert escalates
- Ability to cancel alert from either Helmet HUD or Smartphone app independently
- Visibility of alert status on both helmet HUD and Smartphone app

**Fears**
- False alert sent to emergency services or next of kin without warning
- Panic or legal consequences from false alarms
- Helmet failing to connect to Telemetry or Alerting Infrastructure
- Someone else using their helmet triggering alerts under their identity

**Triggers**
- Powering the helmet on or off
- Cancelling an alert within the 30-second window (via HUD or Smartphone)
- Reviewing connectivity status or ride data on Smartphone app

---

### Smartphone

> **Simulation note:** Two Python scripts used in simulation. Script 1 simulates the Helmet — generates accelerometer, speed, edge processing result, helmet ID, and timestamp, sends to Script 2 via local socket or queue. Script 2 simulates the Smartphone — receives helmet data, adds simulated GPS coordinates and user ID, sends enriched payload to AWS IoT Core. This accurately represents the Helmet → Smartphone → Cloud relay and aggregation architecture.

**Needs**
- Stable Bluetooth connection to Helmet to receive sensor data and edge processing results
- Ability to aggregate helmet data (accelerometer, speed, edge result, helmet ID, timestamp) with phone data (GPS location, user ID) into single enriched payload
- Ability to send enriched payload to Telemetry Infrastructure over mobile data
- Companion app to display alerts, connectivity status, and cancel mechanism
- Local storage to buffer telemetry data if cloud connectivity is lost
- Ability to authenticate rider and helmet to prevent unauthorized use
- Send low battery warning to cloud before phone powers down
- On revival — trigger helmet buffer sync and present retrospective alert to rider
- Act as fallback sensor source if helmet sensors fail (future scope)

**Fears**
- Bluetooth connection to Helmet failing
- Mobile data connectivity lost — no relay path to cloud
- Smartphone is single point of failure for all cloud communication (accepted — backup comms = future scope)
- Phone battery dying without sending low battery warning — cloud cannot distinguish from crash scenario
- Push notification not delivered (Do Not Disturb mode, no signal)
- Failure to register helmet or rider with cloud on first setup
- Buffered crash event lost if phone storage is full when syncing after revival

**Triggers**
- Helmet powers on and initiates Bluetooth pairing
- Crash event detected by helmet edge processing
- Rider opens companion app
- Incoming alert requiring rider acknowledgement or cancellation
- Push notification received from Alerting Infrastructure
- Connectivity loss or reconnection to mobile network
- Phone low battery threshold reached — sends warning to cloud
- Phone comes back online — syncs helmet buffer, presents retrospective alert to rider if crash event found

---

### Next of Kin

**Needs**
- Reliable notification clearly from a verified, genuine source
- Human-friendly message with location and basic incident information
- Simple acknowledgement mechanism (link or button) to confirm receipt

**Fears**
- Malicious actor spoofing alerts to cause panic
- Receiving technical jargon instead of a clear human-readable message
- Alert received with no way to confirm it was acted on

**Triggers**
- Alert dispatched by Alerting Infrastructure after 30-second window expires uncancelled

---

### Emergency Services

**Needs**
- Verified and authenticated alert source
- Precise GPS coordinates and time of incident
- Rider identity and Helmet ID
- Single alert per incident — no duplicates

**Fears**
- Malicious actors sending fake alerts wasting emergency resources
- Duplicate alerts sent for the same incident
- Incomplete or inaccurate location data
- Alert received with no acknowledgement path back to system

**Triggers**
- Alert dispatched by Alerting Infrastructure after 30-second window expires uncancelled

---

### Telemetry Infrastructure

**Needs**
- Persistent listener for incoming telemetry from all active helmets
- Ability to scale up during peak load (e.g. 8am commute surge)
- Ability to scale down during low activity (e.g. 12am–4am)
- Forward telemetry events to Processing Infrastructure
- Receive and relay maintenance flags from helmets
- Relay firmware updates from Fleet Manager pipeline to helmets

**Fears**
- Failure to capture telemetry from active helmets
- Unable to scale fast enough during sudden surge in active helmets
- Failing to scale down — paying for unused capacity
- Forwarding corrupted or out-of-order telemetry to Processing Infrastructure
- Spoofed telemetry received from unauthorized or fake helmet IDs

**Triggers**
- Smartphone transmitting aggregated telemetry payload on behalf of Helmet
- Monitoring Infrastructure health checks
- Infrastructure Engineer performing maintenance or configuration changes
- Firmware update dispatched by Fleet Manager

---

### Processing Infrastructure

> **Design note:** Two-tier architecture. Edge Processing runs on the Helmet. Cloud Processing runs in AWS. Separated in design — may share underlying AWS services in implementation.

#### Edge Processing (Helmet)
- Runs crash detection locally using sensor data
- Sends sensor data AND edge processing result to Smartphone — never directly to cloud
- Helmet provides: accelerometer, speed, edge processing result, helmet ID, timestamp
- Smartphone aggregates helmet data with phone GPS and user ID before sending to cloud
- Operates during connectivity loss — buffers data locally until Smartphone relay is available
- Cancel signal from HUD suppresses alert locally before it reaches Smartphone

#### Cloud Processing (AWS)
- Receives events from Edge Processing via Smartphone → Telemetry Infrastructure → Cloud Processing
- Acts as decision layer — owns all false positive filtering
- Validates crash events against recent telemetry history
- Handles three shutdown types differently:
  - Type 1 (graceful): helmet sent shutdown message → mark offline, no alert
  - Type 2 (battery death): low battery warning received → check last telemetry → countdown only if abnormal acceleration present
  - Type 3 (unexpected dropout): no warning, LWT fired → treat as suspicious → check last telemetry → may trigger alert countdown
- Detects mass false positives across fleet → flags maintenance required
- Detects mass simultaneous alerts → determines infra failure vs real mass incident using active headcount threshold (threshold value stored in Parameter Store, owned by Infrastructure Engineer, changeable without redeployment)
- Forwards confirmed genuine incidents to Alerting Infrastructure
- Forwards maintenance flags to Fleet Manager
- On helmet buffer sync after phone revival — processes buffered crash events and triggers retrospective alert flow to Smartphone app

**Needs**
- Telemetry event stream from Telemetry Infrastructure
- Access to recent telemetry history for crash validation
- Threshold config values from Parameter Store (not hardcoded)

**Fears**
- Unable to receive data from Telemetry Infrastructure
- Unable to differentiate genuine crash from bump, fall, or internet drop
- Receiving duplicate, corrupted, or out-of-order messages
- Forwarding too much raw telemetry to Database causing cost explosion
- Edge processing unit damaged in crash producing invalid events
- Crafted malicious payloads designed to trigger false crashes at scale

**Triggers**
- Telemetry events arriving from Telemetry Infrastructure
- Threshold breach detected across fleet (mass alert pattern)
- Monitoring Infrastructure health check

---

### Alerting Infrastructure

> **Design note:** Alerting Infrastructure is the delivery layer only. It does not filter false positives — that is owned entirely by Processing Infrastructure. Alerting Infrastructure owns deduplication and delivery acknowledgement.

**Needs**
- API endpoint to receive confirmed crash alerts from Processing Infrastructure
- Ability to contact Next of Kin and Emergency Services simultaneously
- Scale to handle mass alert volume without degradation
- Delivery acknowledgement mechanism per alert sent (link or button)
- Deduplication — one alert per incident per recipient

**Fears**
- Unable to scale during mass incident (many crashes simultaneously)
- Alerts delayed — time-critical failure
- Alert sent to wrong next of kin or wrong emergency service region
- Alert delivered but no acknowledgement received — unknown if acted on
- Being used by malicious actor to spam emergency services
- Alert system itself failing while telemetry pipeline remains healthy (must be independently monitored)

**Triggers**
- Confirmed crash event received from Processing Infrastructure
- Rider fails to cancel within 30-second window
- Rider confirms retrospective alert after phone revival
- Monitoring Infrastructure health check

---

### Database

> **Design note:** Two storage tiers. Hot storage handles high-frequency telemetry writes for a limited window. Cold storage handles long-term persistent data. Retention rule: hot storage data expires 24 hours after helmet powers off — not immediately on shutdown.

**Hot Storage**
- Recent telemetry data (short-lived, high write frequency)
- Retained for 24 hours after helmet powers off
- Expires automatically after retention window

**Cold Storage**
- User info and helmet registration
- Next of kin contact details
- Emergency service contacts by region (owned and maintained by Fleet Manager)
- Confirmed incident records (including retrospective incidents confirmed after phone revival)
- Cancelled alert records (rider cancelled — incident still stored)
- False alert logs
- Maintenance records and flags

**Needs**
- High write throughput for hot storage tier
- Reliable long-term persistence for cold storage tier
- Clear data promotion path from hot to cold for flagged incidents

**Fears**
- Storage costs growing uncontrolled from raw telemetry accumulation
- Losing cold storage data (user info, incident records, maintenance history)
- Hot storage becoming a bottleneck at high write volumes
- Data written to wrong storage tier

**Triggers**
- Processing Infrastructure forwarding confirmed incident data
- Telemetry Infrastructure writing recent telemetry to hot storage
- Scheduled hot storage expiry (24 hours post helmet shutdown)
- Helmet buffer sync after phone revival — buffered telemetry written to hot storage, confirmed incidents written to cold storage

---

### Monitoring Infrastructure

**Needs**
- Health checks from: Telemetry Infra, Processing Infra, Alerting Infra, Database, CI/CD Pipeline, Cloud Platform
- Dead man's switch — if monitoring itself goes silent, Infrastructure Engineer is paged automatically
- Dashboard visible to Infrastructure Engineer at all times

**Fears**
- Monitoring Infrastructure itself goes down undetected
- Silent failure — all components report healthy but system is broken (false green — worse than visible failure)
- Alert to Infrastructure Engineer not delivered when failure is detected
- Monitoring health checks interfering with production traffic

**Triggers**
- Scheduled health check intervals per component
- Threshold breach on latency, error rate, or message volume
- Absence of expected signal from any component (silence = failure assumed)
- Infrastructure Engineer manually querying dashboard

---

### CI/CD Pipeline

**Needs**
- Access to infrastructure code repository (Terraform, app code)
- Scoped AWS credentials to deploy infrastructure changes safely
- Automated validation (terraform plan, lint, tests) before any deployment
- Ability to roll back to last known good infrastructure state
- Audit log of every deployment — who, what, when

**Fears**
- Deploying broken infrastructure to production
- Partial deployment — pipeline fails mid-way leaving infra in broken state
- AWS credentials exposed in pipeline logs
- Infrastructure drift — real infrastructure diverges from code without detection
- No rollback path available when a bad deploy is detected

**Triggers**
- Engineer merges code to main branch
- Pull request opened — triggers terraform plan for review
- Scheduled drift detection check
- Manual rollback triggered by Infrastructure Engineer

---

### Infrastructure Engineer

**Needs**
- Unified view of all infrastructure health via monitoring dashboard
- Alerts when any component degrades or fails (on-call paging)
- Ability to deploy, update, and rollback infrastructure via CI/CD Pipeline
- On-call runbook for known failure scenarios
- No access to Fleet Manager firmware pipeline (clear ownership boundary)

**Fears**
- Monitoring Infrastructure goes down with no alert sent
- Pushing a breaking change to production with no rollback path
- Not knowing a change caused an incident until riders report it (reason CI/CD automated testing exists)
- No visibility when infra silently degrades (false green dashboard)
- Being unavailable during a critical incident with no backup

**Triggers**
- Monitoring alert page (on-call)
- Routine infrastructure health review
- Deploying infrastructure changes via CI/CD Pipeline
- Responding to a reported incident
- Scheduled maintenance window

---

### Fleet Manager

> **Design note:** Fleet Manager owns the helmet firmware pipeline independently. Infrastructure Engineer has no access to this pipeline. Two separate pipelines, one owner each.

**Needs**
- Dashboard showing all helmets, status, battery, and connectivity
- View of all active alerts and their resolution status
- Ability to push firmware updates to individual helmets or entire fleet via dedicated pipeline
- Ability to rollback a bad firmware update to previous stable version
- Maintenance flag visibility — which helmets need attention before failure
- Ownership of regional emergency service contact data in cold storage

**Fears**
- Bad firmware update crashing helmet firmware across entire fleet with no rollback path
- Unable to identify degrading helmets before they fail in the field
- Too many simultaneous alerts making triage impossible at scale
- Firmware rollout partially applied — mixed fleet version state with no clear visibility

**Triggers**
- Routine fleet health monitoring
- Maintenance flag raised by Processing Infrastructure
- Firmware update ready for deployment
- Mass alert event requiring fleet-level triage

---

### Cloud Platform

**Needs**
- VPCs, subnets, and security groups to isolate infrastructure components
- IAM roles with least privilege per service — no over-permissioned roles
- Compute resources that scale with load (serverless preferred where possible)
- Managed database services with vertical scaling for write throughput
- Budget alerts and cost visibility dashboards
- Audit logging for all infrastructure access and changes

**Fears**
- Cloud region or service outage (beyond project scope — acknowledged)
- Misconfigured IAM exposing infrastructure, data, or APIs
- Misconfigured auto-scaling causing runaway costs
- Bad configuration pushed by engineer causing infra failure or cost spike
- AWS service limits hit unexpectedly during traffic surge
- Secrets or credentials accidentally committed to code repository

**Triggers**
- Infrastructure Engineer or CI/CD Pipeline deploys or modifies resources
- Auto-scaling event triggered by load increase or decrease
- Budget threshold breached
- Security event detected (unauthorized access attempt)

---

*Next phase: Data Flow Document*