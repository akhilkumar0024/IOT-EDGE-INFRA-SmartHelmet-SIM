# Smart Helmet — Flow Reference Card

> Quick lookup for all completed flows. Use this to find what was decided without re-reading the full flow document.
> For full step-by-step detail → `Data-Flow-Doc-Formatted.md`
> For architecture decisions → `Project-Context-Universal.md`

---

## Flow 1 — Startup Sequence (Happy Path)

**Precondition:** Rider powers on helmet. Bluetooth pairing succeeds. Cloud is reachable.

**What it covers:**
- Bluetooth pairing → cloud connectivity check → sensor health check
- Parameter Store thresholds (battery %) fetched at startup via smartphone relay and stored locally on helmet
- Smartphone subscribes to `helmet/{helmet_id}/infra/status` MQTT topic at session startup
- LWT registered at session startup as part of MQTT connection setup

**Branch A — Health Check Pass:**
- Buffer check runs immediately after health check
- If buffer empty → straight to Normal Telemetry
- If buffer non-empty → catch-up sync first, then Normal Telemetry

**Branch B — Health Check Fail:**
- Maintenance flag sent to cloud → written to Cold Storage
- Helmet stops all sensor transmission
- Rider notified on HUD: alert mechanism offline

**Normal Telemetry (after startup):**
- Helmet → Smartphone: every 1 second
- Smartphone → Telemetry Infra: JSON batch of 10 payloads every 10 seconds (includes GPS, user ID)
- Telemetry Infra → Hot Storage: one write per batch

**Key decisions:**
- Smartphone is the aggregator — helmet never talks to cloud directly
- Firmware version included in every payload (enables crash-firmware correlation later)

---

## Flow 2 — Startup Sequence Sad Paths

### Sad Path 1 — Bluetooth Pairing Fails
**Precondition:** Helmet on, Bluetooth pairing fails to establish.

- Retry loop: up to 5 attempts per power-on
- After 5 fails: rider notified on HUD, helmet enters standalone buffer-only mode
- Local retry counter incremented on helmet on each fail (persists across power-ons)
- At 50 cumulative retries → HUD warns rider to seek maintenance
- Counter reset only by Fleet Manager authorised command → logged to Cold Storage with timestamp
- On future successful pairing → buffer + cumulative retry count sync'd to cloud

### Sad Path 2A — Smartphone Has No Internet
**Precondition:** Bluetooth paired, no internet on smartphone.

- Rider notified on both devices
- Smartphone buffers locally every 1 second
- On restore: backlog split into 50-second chunks → Catch-up Channel
- Live telemetry resumes on Live Channel simultaneously with catch-up flush
- Smartphone clears local storage only after full backlog flush confirmed

### Sad Path 2B — Telemetry Infrastructure Unreachable
**Precondition:** Bluetooth paired, internet up, Telemetry Infra not responding.

- Same buffering behaviour as 2A
- Monitoring Stack detects and pages Infrastructure Engineer
- `infra/status` MQTT topic used to notify rider of cloud outage and restoration

### Sad Path 2C — Buffer Sync Fails on Forward to Telemetry Infra
**Three cases:**
- **DB Full:** Infra returns error → smartphone holds → engineer provisions → retry
- **Corrupt Data:** Infra rejects → smartphone requests helmet resend → one retry → if still rejected: discard, log to Cold Storage, both buffers cleared
- **Ack Lost:** Idempotency + TTL. 3 retries with 30s timeout. On all 3 fail: chunk marked unconfirmed, retried on next connectivity restore. TTL = 24 hours (Parameter Store) — after expiry: discard, Cold Storage log, engineer alerted.

**Key decisions:**
- Helmet buffer never cleared until sync confirmation received from Telemetry Infra via Smartphone
- Chunks are all-or-nothing (resend full chunk on any failure)
- Duplicate chunks detected by timestamp range → discarded and acknowledged (idempotency)

---

## Flow 3 — Crash Detection and Alert Flow

**Precondition:** Mid-ride, normal conditions, cloud reachable.

**Crash path:**
- Crash flag detected by edge processing on helmet
- Embedded in standard telemetry payload → Smartphone → IoT Core → Telemetry Infra
- Telemetry Infra inspects batch → writes crash data point to **SQS Crash Queue**
- Processing Infra reads from SQS → queries Hot Storage → validates

**Branch A — False Positive:**
- Processing Infra confirms false positive → drops label into **SQS Alert Queue**.
- Alerting Infra takes over: publishes 5-second override window via IoT Core to devices.
- A1: Rider does nothing → Alerting Infra logs to Cold Storage. No alert.
- A2: Rider overrides (via IoT Core) → fresh 30-second countdown starts.

**Branch B — Genuine Crash → Alert Countdown:**
- Processing Infra drops confirmed flag into **SQS Alert Queue**.
- Alerting Infra reads queue and owns the 30-second countdown via IoT Core.
- Displayed on both HUD and Smartphone simultaneously.
- Only one cancel signal needed (sent via IoT Core).
- If cancelled → Alerting Infra logs to Cold Storage. No alert.
- If not cancelled → Next of Kin and Emergency Services alerted independently.
- Next of Kin receives: incident location, current location only (hostile actor consideration).

**Key decisions:**
- Crash flag is a field in the telemetry payload — NOT a separate MQTT topic.
- Telemetry Infra is the only service writing to SQS Crash Queue.
- Processing Infra validates but is stateless regarding alerts; it hands off all completed validations (even false positives) to **SQS Alert Queue**.
- Alerting Infra manages all user interactive states (via AWS Step Functions) and final Cold Storage writes for incident logs.

---

## Flow 4 — Phone Dead During Crash

**Precondition:** Smartphone is completely dead. Helmet active. No Bluetooth connection.

- No countdown. No alert window. Helmet stores crash event + surrounding telemetry in buffer.
- Helmet continues sensing and buffering every 1 second.

**On phone revival:**
- Normal startup runs (Bluetooth pair → cloud connectivity → buffer check)
- Buffer syncs via Catch-up Channel — crash flag is just another datapoint in the backlog
- Telemetry Infra inspects synced chunks for crash flag → SQS Crash Queue → Processing Infra validates

**Case A (within 24 hours):** Hot Storage available → Branch A or B validation → if genuine → Retrospective Alert
**Case B (beyond 24 hours):** No Hot Storage → Processing Infra escalates direct to rider → Retrospective Alert

**Retrospective Alert:**
- Persistent notification published by Alerting Infra via IoT Core to both devices (no countdown, rider must act).
- Rider confirms (via IoT Core) → alert fires to Next of Kin + Emergency Services.
- Rider cancels (via IoT Core) → Alerting Infra logs to Cold Storage, no alert.
- Rider unreachable → Alerting Infra logs to Cold Storage, no alert.

**Key decisions:**
- Flow 5 (Retrospective Alert After Phone Revival) absorbed into Flow 4
- Same mechanic applies regardless of reason for delay (phone dead, no internet, infra unreachable)

---

## Flow 5 — Retrospective Alert After Phone Revival

> **Absorbed into Flow 4.** See Flow 4 — Retrospective Alert section.

---

## Flow 6 — Graceful Shutdown

**Precondition:** Rider switches helmet off deliberately.

**Happy Path:**
- Remaining unsent telemetry flushed first → then graceful shutdown message sent
- Processing Infra receives shutdown message → marks helmet gracefully offline
- Ack sent back → helmet powers down on ack
- No cold storage write. No alert. Normal event.
- Hot Storage 24-hour retention window starts from last telemetry batch timestamp.

**Sad Path — Ack not received within 10 seconds:**
- Helmet powers down, buffer retained
- From cloud perspective: no shutdown received → LWT fires → Flow 8 runs independently
- Smartphone retains buffer including shutdown message
- On connectivity restore → buffer syncs → Processing Infra receives shutdown retroactively

**Scenario 1 — Flow 8 was a false positive, no alert fired:**
- Graceful shutdown confirmed, telemetry written to Hot Storage, rider notified session ended safely

**Scenario 2A — Alert countdown still active when buffer arrives:**
- Countdown cancelled, rider informed, rider given option to manually alert Emergency Services
- Rider choice logged either way

**Scenario 2B — Alert already fired before buffer arrives:**
- Rider informed alert already sent, given option to notify Next of Kin + Emergency Services that rider is safe
- Notification goes through Alerting Infra same as normal alert

---

## Flow 7 — Battery Death

**Precondition:** Mid-ride. Battery dropping.

**10% threshold:** Low battery warning → cloud marks helmet as low battery. Operations continue normally.

**5% threshold:** Shutdown message sent with last telemetry. 15-second ack timer starts.

**Case 1 — No crash flag in last telemetry:**
- Cloud marks battery death offline, sends ack, helmet powers down. No alert. Normal event.

**Case 2 — Crash flag in last telemetry:**
- Processing Infra validates → false positive: logged, ack sent, helmet powers down
- Genuine crash: alert mechanics initiated (30-second countdown) → ack sent immediately after mechanics initiated, NOT after countdown resolves
- Helmet may die during countdown — cloud owns countdown regardless, smartphone carries it alone

**Sad Path — 15-second timer expires, no ack received:**
- Helmet powers down, buffer retained
- Same retroactive resolution logic as Flow 6 Sad Path scenarios

**Key decisions:**
- 5% battery = at least 1 minute on any commercially viable device — full alert window fits
- Both thresholds stored in Parameter Store, read at startup via smartphone relay, cached locally on helmet for session

---

## Flow 8 — Unexpected Dropout / LWT

**Precondition:** Mid-ride. Smartphone disconnects from IoT Core unexpectedly. No warning sent.

- LWT fires from IoT Core → routed to **SQS LWT Queue** → Processing Infra reads
- 5-second grace period timer starts on LWT receipt

**Grace period — device reconnects within 5 seconds:** LWT discarded, no log, normal resumption.

**Grace period expires — genuine dropout:**
- Processing Infra queries Hot Storage for last telemetry

**Case 1 — No crash flag:** Mark as unexpectedly offline, log to Cold Storage. No alert.

**Case 2 — Crash flag present:**
- Validate → false positive: Cold Storage log, no alert
- Genuine crash: 30-second countdown on both devices (smartphone may be gone — cloud runs countdown anyway)
- Rider cancels → logged, no alert
- Rider doesn't cancel / smartphone unreachable → alert fires to Next of Kin + Emergency Services

**Smartphone comes back after alert already fired:**
- Same retroactive resolution as Flow 6 Scenario 2B (rider offered safe notification option)

**Key decisions:**
- LWT routes to SQS LWT Queue (not directly to Processing Infra) — survives Processing Infra outages
- LWT does NOT fire on Bluetooth drop — MQTT session is Smartphone↔IoT Core, not Helmet↔IoT Core
- LWT cannot fire if IoT Core itself is down — known limitation

---

## Flow 9A — Monitoring Stack and Detection

**What it is:** The detection and alerting chain that underpins all Flow 9 sub-flows.

**Stack:** Prometheus + Alertmanager + Grafana on ECS Fargate. CloudWatch + SNS for IoT Core + DB. PagerDuty as single paging destination.

**Health check frequencies:** IoT Core every 30 seconds. All other components every 60 seconds.

**Dead man's switch:** Monitoring Infra sends heartbeat to Healthchecks.io every 60 seconds. If heartbeat stops → PagerDuty pages engineer.

**Alert routing:**
- Cloud infra failures → Infrastructure Engineer via PagerDuty
- Firmware mass alerts → Fleet Manager via PagerDuty

**Mass Alert Decision Tree:**
1. Geographic clustering check: clustered → real incident → fire alerts, engineer monitors load
2. If dispersed → firmware version correlation check
   - Correlated to firmware version → likely bug → alerts held → Fleet Manager paged
   - Spans all firmware versions → likely infra misclassification → alerts held → Infra Engineer paged

---

## Flow 9B — Sensor Failure (Device Layer)

**Single helmet failure:** Processing Infra false positive logic catches it. See Flow 1 Branch B (maintenance flag) and Flow 3 Branch A (false positive). No new infra behaviour.

**Fleet-wide failure (firmware bug):** Enters via Flow 9A Branch B1 (firmware correlated mass alert).
- Riders notified: "Fleet-wide issue — alert systems under maintenance"
- Fleet Manager investigates
- **Outcome 1 (firmware bug confirmed):** All held alerts discarded, logged to Cold Storage with firmware bug remark, riders notified systems restored
- **Outcome 2 (no firmware bug found):** Held alerts re-validated individually
  - Under 24 hours → Branch A validation (Hot Storage available)
  - Over 24 hours → Branch B retrospective alert (same as Flow 4)
  - Rider unreachable → Cold Storage log, no alert fired

---

## Flow 9C — Helmet Telemetry to Smartphone Failure (Device Layer)

**Precondition:** Mid-ride Bluetooth link between Helmet and Smartphone drops unexpectedly.

- Helmet buffers locally. Smartphone discards partial batch and notifies cloud via `bluetooth_disconnected` topic.
- Processing Infra checks last telemetry for crash flag.
- **No crash flag:** Log to Cold Storage, no alert.
- **Crash flag:** Validation + alert mechanics identical to Flow 8 Case 2.

**On Bluetooth restore:**
- Smartphone publishes `bluetooth_restored` → Processing Infra marks restored
- Catch-up sync runs (identical to Flow 2 Sad Path 2A)
- If crash flag found in synced data → retrospective alert (Flow 4)

**Key decisions:**
- LWT does NOT fire on Bluetooth drop (Smartphone MQTT session stays active)
- Smartphone publishes both disconnect and restore events — helmet cannot

---

## Flow 9D — Smartphone Telemetry to Cloud Failure (Device Layer)

> No new infrastructure behaviour. All scenarios reference existing flows:
> - Internet loss → Flow 2 Sad Path 2A
> - Telemetry Infra unreachable → Flow 2 Sad Path 2B
> - IoT Core failure → Flow 9E
> - Smartphone device or app failure → out of scope (cloud detects silence, Flow 8 runs)

---

## Flow 9E — IoT Core / MQTT Broker Failure (Cloud Layer)

**Precondition:** IoT Core becomes unreachable mid-ride.

**Branch A — Internet loss:** Smartphone buffers. See Flow 2 Sad Path 2A.
**Branch B — IoT Core down (internet up):** Smartphone buffers. Rider notified.
- Cloud side: CloudWatch → SNS → PagerDuty → Infra Engineer

**On recovery:**
- Smartphone reconnects, re-registers LWT automatically as part of MQTT reconnect
- Catch-up sync runs (identical to Flow 2 Sad Path 2A)

**Known limitation:** LWT cannot fire during IoT Core outage. Any crash during outage handled retrospectively via Flow 4 mechanic.

---

## Flow 9F — Telemetry Infrastructure Failure (Cloud Layer)

**Precondition:** IoT Core is up. Telemetry Infra goes down.

- Smartphone MQTT session remains active throughout — no reconnect needed
- Monitoring Infra publishes `infra/status` to notify all active riders
- Helmet and Smartphone continue operating normally. All telemetry buffered locally on Smartphone.

**Processing Infra during outage:** Drains any pre-failure crash events already in SQS queues. Then goes idle. Pre-failure events processed normally (Hot Storage data valid).

**On recovery:**
- Prometheus detects → Alertmanager → PagerDuty → Infra Engineer
- `infra/status` restored notification published to all active riders
- Catch-up sync runs for all buffered data

**Known limitation:** Real-time crash alerts cannot fire during Telemetry Infra outage — it is the only service that writes to SQS Crash Queue.

---

## Flow 9G — Processing Infrastructure Failure (Cloud Layer)

**Precondition:** IoT Core and Telemetry Infra are up. Processing Infra goes down.

- Telemetry pipeline continues normally throughout — no dependency on Processing Infra
- Crash data points → SQS Crash Queue (accumulate unread)
- Control messages → SQS Control Queue (accumulate unread)
- LWT messages → SQS LWT Queue (accumulate unread)
- All three queues retain messages for **14 days** (independent of Hot Storage 24-hour expiry)
- Rider notified via `infra/status`: alert system failure

**Shutdown during outage:** Helmet ack timer expires, powers down, buffer retained. LWT does NOT fire (MQTT session stays active).

**On recovery — Queue drain order (guaranteed):**
1. **Control Queue first** — state updates (know which helmets are gracefully offline)
2. **LWT Queue second** — if helmet already marked offline by Control Queue drain → discard LWT. Otherwise process as Flow 8 (with >24 hour Hot Storage expiry check).
3. **Crash Queue last** — full state context available. Branch A (<24 hours, Hot Storage available) or Branch B (>24 hours, retrospective alert to rider).

**DLQ:** Catches messages that fail to process after recovery (code bug). NOT for outage buffering.

**Known limitation:** Events unprocessed after 14 days expire from SQS with no cold storage record — 14-day outage is a catastrophic failure beyond design scope.

---

## SQS Queue Summary (Quick Reference)

| Queue | Source | Consumer | Retention | Purpose |
|---|---|---|---|---|
| SQS Crash Queue | Telemetry Infra | Processing Infra | 14 days | Crash event data points |
| SQS Control Queue | Telemetry Infra | Processing Infra | 14 days | Low battery, shutdown, battery death |
| SQS LWT Queue | IoT Core rules engine | Processing Infra | 14 days | Unexpected dropout events |
| SQS Alert Queue | Processing Infra | Alerting Infra | 14 days | Validated crash events, false positives |

---

## Key Cross-Flow References

| Scenario | Primary Flow | Referenced By |
|---|---|---|
| Retrospective alert mechanic | Flow 4 | Flow 6, 8, 9B, 9C, 9E, 9G |
| Catch-up sync (backlog flush) | Flow 2 Sad Path 2A | Flow 4, 9C, 9E, 9F |
| Alert countdown (30s window) | Flow 3 | Flow 7, 8, 9B |
| False positive handling (5s override) | Flow 3 Branch A | Flow 7, 8 |
| Graceful shutdown retroactive resolution | Flow 6 Sad Path Scenario 2A/2B | Flow 7, 8 |
| Mass alert decision tree | Flow 9A | Flow 9B |
| Buffer sync failure (3 cases) | Flow 2 Sad Path 2C | Implied by all catch-up flows |

---

*Reference card version: Post-Alerting-Decoupling*
*Last updated: 2026-03-29*
