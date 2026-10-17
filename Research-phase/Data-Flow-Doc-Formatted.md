# Smart Helmet — Data Flow Documentation

> **Document status:** This document has been reconciled against the actual implemented
> codebase. Each flow carries an explicit implementation status so design-only content is
> never mistaken for working behaviour.
>
> - ✅ **Implemented** — behaviour exists in the current codebase.
> - 🟡 **Partial** — some parts implemented, remainder is design.
> - 🔴 **Design only** — reference design, not implemented. Device-layer concepts
>   (helmet firmware, smartphone app, Bluetooth, local buffering) cannot be exercised by
>   the current simulator and are documented as design intent.

---

## Table of Contents

- [Flow 1 — Startup Sequence (Happy Path)](#flow-1--startup-sequence-happy-path)
- [Flow 2 — Startup Sequence Sad Paths](#flow-2--startup-sequence-sad-paths)
- [Flow 3 — Crash Detection and Alert Flow](#flow-3--crash-detection-and-alert-flow)
    - [Implemented telemetry & alert pipeline](#implemented-telemetry--alert-pipeline)
    - [True crash (STD_CD) alert countdown](#true-crash-std_cd-alert-countdown)
    - [False positive (FP_CD) override window](#false-positive-fp_cd-override-window)
    - [FP override → standard upgrade (Case A)](#fp-override--standard-upgrade-case-a)
    - [Late FP override fail-safe (Case B)](#late-fp-override-fail-safe-case-b)
    - [Cancellation](#cancellation)
    - [Design only: contact lookup and delivery](#design-only-contact-lookup-and-delivery)
- [Flow 4 — Phone Dead During Crash (retrospective)](#flow-4--phone-dead-during-crash-retrospective)
- [Flow 5 — Retrospective Alert After Phone Revival](#flow-5--retrospective-alert-after-phone-revival)
- [Flow 6 — Graceful Shutdown & Device Lifecycle](#flow-6--graceful-shutdown--device-lifecycle)
- [Flow 7 — Battery Death](#flow-7--battery-death)
- [Flow 8 — Unexpected Dropout / LWT](#flow-8--unexpected-dropout--lwt)
- [Flow 9 — Infrastructure Failure, Monitoring & Mass Alerts](#flow-9--infrastructure-failure-monitoring--mass-alerts)
    - [9A — Monitoring Stack and Detection](#flow-9a--monitoring-stack-and-detection)
    - [9B — Sensor Failure](#flow-9b--sensor-failure)
    - [9C — Helmet Telemetry to Smartphone Failure](#flow-9c--helmet-telemetry-to-smartphone-failure)
    - [9D — Smartphone Telemetry to Cloud Failure](#flow-9d--smartphone-telemetry-to-cloud-failure)
    - [9E — IoT Core / MQTT Broker Failure](#flow-9e--iot-core--mqtt-broker-failure)
    - [9F — Telemetry Infrastructure Failure](#flow-9f--telemetry-infrastructure-failure)
    - [9G — Processing Infrastructure Failure](#flow-9g--processing-infrastructure-failure)
    - [9H — Alerting Infrastructure Failure](#flow-9h--alerting-infrastructure-failure)
    - [9I — Database Failure](#flow-9i--database-failure)
    - [9J — Parameter Store Unavailability](#flow-9j--parameter-store-unavailability)
    - [9K — Bad Firmware Update](#flow-9k--bad-firmware-update)
    - [9L — Bad Infrastructure Deploy — CI/CD](#flow-9l--bad-infrastructure-deploy--cicd)
    - [9M — Monitoring Stack Failure](#flow-9m--monitoring-stack-failure)
- [Flow 10 — Firmware Update](#flow-10--firmware-update)
- [Flow 11 — Scale Up / Scale Down](#flow-11--scale-up--scale-down)
- [Known Limitations](#known-limitations)
- [Future Enhancements (Post-MVP)](#future-enhancements-post-mvp)

---

## Architecture Overview (as implemented)

```
Helmet (simulator) ──MQTT──▶ AWS IoT Core
                                │ rules engine
   telemetry ──────────────▶ Telemetry Queue → telemetry-processor → Hot Storage (DynamoDB)
   crash flag in batch ────▶ Crash Queue → processing-engine → validates → Alert Queue
   control (online/shutdown)→ Control Queue → processing-engine → Device Status Table
   LWT ────────────────────▶ LWT Queue → processing-engine → checks Device Status Table
   override (cancel/FP) ───▶ Override Queue → alert-handler
   alert/countdown (c2d) ◀── helmet/{id}/alert/status ← alert-handler (IoT publish)

alert-handler ──▶ Step Functions (countdown timer + audit writes)
               ──▶ Execution Registry (lease ownership)
               ──▶ SES email (notification)
```

**Transport model (corrected):** Telemetry Infrastructure is an **SQS queue consumer**, not an
HTTP service behind a load balancer. The IoT Core rules engine delivers directly to SQS.

**Two DynamoDB tables, two distinct purposes (corrected):**

| Table | Written by | Read by | Purpose |
|---|---|---|---|
| `smart-helmet-device-status` | processing-engine | processing-engine | Helmet lifecycle: last known `ONLINE` / `GRACEFUL_SHUTDOWN`. Used to disambiguate LWT. TTL 900s |
| `smart-helmet-execution-registry` | alert-handler + Step Functions | alert-handler + Step Functions | Alert lease ownership: one active countdown per helmet (`ownerIncidentId` guard). TTL = deadline + 86400s |

---

## Flow 1 — Startup Sequence (Happy Path)

> **Implementation status:** 🔴 Design only.
>
> Device-layer behaviour (Bluetooth pairing, sensor health checks, buffer management) is
> design intent. The simulator connects straight to AWS IoT Core with an X.509 certificate,
> publishes `ONLINE` on the control topic, registers its Last Will and Testament (LWT), and
> subscribes to the alert/status topic. There is no smartphone relay in the simulator.

### Cloud Connectivity & Session Start (as implemented in simulator)

```
[Simulator] → [AWS IoT Core]            : MQTT session established (X.509)  : on start
[Simulator] → [AWS IoT Core]            : publish helmet/{id}/control {status: ONLINE}  : immediately after connect
[AWS IoT Core] → [SQS Control Queue]    : ONLINE message                      : via iot_control_rule
[processing-engine] → [Device Status]   : mark helmet ONLINE (TTL 900s)       : on read
[Simulator] → [AWS IoT Core]            : register LWT on helmet/{id}/lwt     : on connect
[Simulator] → [AWS IoT Core]            : subscribe helmet/{id}/alert/status  : on connect
```
<!-- Design intent (Bluetooth pair, sensor health check, buffer check, live/catch-up channels) omitted — see section 1 annex. -->

### Design Annex — Device-Layer Behaviour (not implemented)

The following device-layer concepts were part of the original design and remain valid
intent for physical hardware:

- Bluetooth pairing between helmet and smartphone, with a 5-attempt retry loop per power-on.
- Sensor health check on startup; failure raises a maintenance flag (Branch B below).
- Local helmet buffer for telemetry during connectivity loss; buffer sync when connection restores.
- Smartphone aggregates helmet data with GPS/user ID and batches to cloud every 10 seconds.
- Live channel and 50-second-chunk catch-up channel with chunk acknowledgement and
  duplicate detection (see Flow 2 Design Annex).

---

## Flow 2 — Startup Sequence Sad Paths

> **Implementation status:** 🔴 Design only.
>
> All sad paths in this section are device-layer (retry loops, local buffering, catch-up
> channels, ack/TTL handling on the device). None are exercised by the simulator or the
> cloud services. They remain valid design intent for physical hardware and future
> firmware/app work.

### Design Annex — Retry and Buffering Behaviour

- **Bluetooth pairing fails:** 5 retries per power-on; helmet retains buffer and never
  clears it without a cloud sync acknowledgement; cumulative retry counter (50) triggers
  a maintenance recommendation.
- **Smartphone no internet / Telemetry Infrastructure unreachable:** smartphone buffers
  locally; on restore, flushes backlog in 50-second chunks via the catch-up channel,
  resending unacknowledged chunks (up to 3 attempts), discarding duplicates by timestamp
  range, and finally clearing device buffers. Unconfirmed chunks expire via TTL (24h).
- **Buffer sync fails (DB full / corrupt / ack lost):** chunk retained until acknowledged;
  corruption triggers a resend request and ultimately a discard-and-log path; ack loss is
  handled by idempotency + TTL.
- **Fleet Manager counter reset** flows through the fleet management interface.

> These behaviours are **not implemented** in code. They are captured as design for a
> future device SDK / firmware. The cloud infrastructure needed to *receive* such data
> (SQS queues, Hot Storage, idempotent inserts) exists, but nothing generates these
> device-side flows today.

---

## Flow 3 — Crash Detection and Alert Flow

> **Implementation status:** ✅ Implemented (core pipeline — with corrections).
>
> This is the baseline crash → validation → countdown → cancellation → notification
> pipeline. It is the most important flow and is fully implemented across
> `telemetry-processor`, `processing-engine`, `alert-handler`, Step Functions, and the
> DynamoDB tables.

### Implemented telemetry & alert pipeline

```
[Helmet Sensors] → [Helmet (sim)]        : telemetry batch with crash_flag    : every 1s (sim batches)
[Helmet (sim)] → [AWS IoT Core]          : publish helmet/{id}/telemetry      : on batch
[AWS IoT Core] → [SQS Telemetry Queue]   : telemetry batch                    : via iot_telemetry_data_rule
[telemetry-processor] → [Hot Storage]    : write batch row (TTL 24h)          : on receive
[telemetry-processor] → [SQS Crash Queue] : crash event (if crash_flag)       : on batch with crash flag
[processing-engine] → [SQS Crash Queue]  : read crash event                   : event-driven
[processing-engine] → [Hot Storage]      : query 15s window prior to crash    : immediately
[processing-engine] → [processing-engine] : validate (max speed > 10 → STD_CD / FP_CD)
[processing-engine] → [SQS Alert Queue]  : alert event (alert_type, incident_id) : on validation
[alert-handler] → [SQS Alert Queue]      : read alert event                   : event-driven
```

**Validation rule (as implemented):** processing-engine queries Hot Storage for the 15
seconds before the crash timestamp using `helmetId = X AND timestamp BETWEEN (t-15, t)`.
Each stored row may be a batch (`telemetry: [...]` array) or a single datapoint. It flattens
to all datapoints. If no telemetry is found, the crash is degraded to `retrospective`
(low-confidence, rider decides). Otherwise: `max_speed > 10` → `STD_CD` (true crash),
else `FP_CD` (false positive).

**Alert events are deduplicated/idempotent:** `incident_id` is a deterministic
`uuid5(NAMESPACE_URL, helmet:timestamp:location:speed)`; Step Functions executions are named
by `incident_id`, so a duplicate alert message cannot start two countdowns.

### Lease ownership model (corrected — replaces the old "PENDING / execution ARN" design)

The Execution Registry enforces **one active alert countdown per helmet** via conditional
writes. This replaced the earlier design that stored a raw execution ARN and called
`StopExecution`.

```
Key:        helmetId
Fields:     ownerIncidentId   — the incident that owns this lease
            status            — INITIALIZING → STD_CD | FP_CD → CONFIRMED
                                | FALSE_POSITIVE_DISMISSED | CANCELLED
            countdownStatus   — STD_CD for standard/retro, FP_CD for false positive
            alertType         — STD_CD | FP_CD | retrospective
            incidentTimestamp
            serverDeadline    — unix deadline (start + wait window)
            executionArn
            TimeToExist       — serverDeadline + 86400 (belt-and-suspenders cleanup)
```

`alert-handler.acquire_lease()` writes the lease with a **conditional expression** that
fails if another incident owns it (or if the row exists with a newer timestamp). This is the
same mechanism that fences the FP→STD upgrade (see below). The Step Functions state machine
read-backs the lease at countdown expiry and only acts if `ownerIncidentId` still matches its
own `incident_id` — the execution ARN is no longer the ownership token.

### True crash (STD_CD) alert countdown

```
[alert-handler] → [Execution Registry]   : acquire lease (INITIALIZING)       : before StartExecution
[alert-handler] → [AWS Step Functions]   : StartExecution(name=incident_id)   : immediately
[alert-handler] → [Execution Registry]   : update lease → STD_CD + executionArn
[alert-handler] → [AWS IoT Core]         : publish START_COUNTDOWN to helmet/{id}/alert/status
[alert-handler] → [SQS Alert Queue]      : delete message                     : immediately
```

### Step Functions countdown (SDK Integration, no compute)

Step Functions owns the timer and the audit writes via **SDK Integration steps** (native
`aws-sdk` / `dynamodb` service calls from the ASL — no Lambda, no long-running container).

```
WaitWindow(wait_seconds from $) → ReadActiveLease (DynamoDB GetItem)
  → CheckLease (Choice):
      owner matches AND status = CANCELLED        → WriteCancelledIncident → DeleteCancelledLease
      owner matches AND status = FP_CD            → DismissFalsePositive  → DeleteFalsePositiveLease
      owner matches AND status = STD_CD           → ConfirmIncident       → SendAdminAlert → DeleteConfirmedLease
      anything else (including lease gone)        → SilentExit
      (ConfirmIncident/Dismiss/Delete all fail silently on ConditionalCheckFailed → SilentExit)
```

- `wait_seconds` comes from the SSM parameter for the alert type (see table below).
- `SendAdminAlert` sends an **SES email to the configured address**
  (subject includes `incident_id`). This is a replacement for the design's richer
  "Next of Kin + Emergency Services contact lookup" — see Design only section.
- Each `UpdateItem`/`DeleteItem` uses `ConditionExpression = ownerIncidentId : incident AND
  status : expected`, so a lease stolen by a newer incident causes the old execution to
  `SilentExit` — no double alert, no double audit write.

### Alert type determination (as implemented)

`alert-handler` reads `alert_type` from the alert event and picks the window:

| alert_type | Window | Lifecycle |
|---|---|---|
| `FP_CD` | 5s (SSM `false_positive_window_seconds`) | Unless overridden → dismiss, log `FALSE_POSITIVE_DISMISSED` |
| `STD_CD` | 30s (SSM `standard_alert_window_seconds`) | Unless cancelled → confirm, SES alert |
| `retrospective` | 300s (SSM `retrospective_alert_window_seconds`) | Unless cancelled → confirm, SES alert |

> **Note (corrected):** The design included a "standard → retrospective downgrade"
> threshold check on elapsed time. **Not implemented.** `STD_CD` events always run a 30s
> countdown regardless of age; delayed events surface as `retrospective` because
> processing-engine cannot find telemetry (degradation happens at the processing-engine
> stage, before alert-handler).

### False positive (FP_CD) override window

```
[alert-handler] → [Execution Registry]   : acquire lease FP_CD                  : on FP_CD alert
[alert-handler] → [AWS Step Functions]   : StartExecution(wait 5s)              :
[alert-handler] → [AWS IoT Core]         : publish START_COUNTDOWN              :
```

If the rider does nothing, the SFN quietly dismisses the false positive
(writes `FALSE_POSITIVE_DISMISSED` to Cold Storage, deletes the lease) — mirroring the
safety goal of not paging emergency services for a false alarm.

### FP override → standard upgrade (Case A)

> ✅ Implemented. Rider overrides a false positive to convert it to a genuine crash alert.

```
[Rider] → [helmet/{id}/alert/override]   : action = FP_OVERRIDE, incident_id   : within the FP window
[AWS IoT Core] → [SQS Override Queue]    : override message                    : via iot_override_alert_rule
[alert-handler] → [SQS Override Queue]   : read override                       : event-driven
[alert-handler] → [Execution Registry]   : verify lease ownerIncidentId matches
[alert-handler] → [Execution Registry]   : acquire lease for new incident (STD_CD) fenced on
                                          owner still holding the FP lease + status==FP_CD
[alert-handler] → [AWS Step Functions]   : StartExecution — fresh 30s STD_CD countdown
[alert-handler] → [AWS IoT Core]         : publish START_COUNTDOWN (30s)
```

The old FP execution, on waking, reads the lease, sees it no longer owns
(`ownerIncidentId` changed), and exits `SilentExit` — without writing a dismissal.

### Late FP override fail-safe (Case B)

> ✅ Implemented (this conversation). If the FP execution already expired (lease deleted)
> *before* the override was dequeued, the rider's request for help is **not** silently
> dropped — a fresh 30s `STD_CD` countdown is started anyway. The only exception is a lease
> currently held by a *different* incident, which is left untouched.

```
[alert-handler] → [Execution Registry]   : lease lookup
   if lease exists & owner == incident   → Case A upgrade (above)
   else if no lease (FP expired)         → start fresh STD_CD countdown,
                                            using incident_timestamp from the override message
   else (lease owned by another incident) → log, drop message
```

Idempotency is preserved because the derived incident id is deterministic, so a duplicate
override cannot double-start. This closes the Scenario 2B fail-safe gap from the original
design doc.

### Cancellation

```
[Rider] → [helmet/{id}/alert/override]   : action = CANCEL, incident_timestamp : within the window
[AWS IoT Core] → [SQS Override Queue]    : cancel message                       : via iot_override_alert_rule
[alert-handler] → [SQS Override Queue]   : read cancel                          : event-driven
[alert-handler] → [Execution Registry]   : lookup lease
   if lease active (STD_CD/FP_CD/INITIALIZING, not yet expired)
        → set lease status = CANCELLED (conditional write), publish DISMISS
   else if a confirmed incident exists in Cold Storage
        → start Reconciliation SFN (stand-down email if now - ts <= 300s)
   else → log, drop
```

- The countdown SFN, on waking with status `CANCELLED`, writes `INCIDENT_CANCELLED` and
  deletes the lease. No alert fires.
- **Late cancellation** (window already expired, lease gone) is handled by the
  **Reconciliation state machine** — it re-checks the incident in Cold Storage and, if within
  the 5-minute reconciliation window, emails a stand-down notice and marks the record
  `RESOLVED_BY_LATE_CANCEL`.
- **No `StopExecution` is ever called.** The ASL runs to completion and reads the lease
  status. This is the correct, current behaviour.

### Design only: contact lookup and delivery

- **Not implemented:** lookup of next of kin / emergency service contacts from Cold Storage,
  per-channel delivery (SMS/email) with per-channel retries and delivery-outcome logging.
- **Implemented instead:** Step Functions sends an SES email to a single configured address
  (hardcoded in Terraform `sns-email-address`). There is no emergency-services/next-of-kin
  split.
- **Design intent (future):** enrich Cold Storage with rider profile + emergency contacts;
  split delivery paths; capture per-channel delivery outcomes in the incident audit record.

---

## Flow 4 — Phone Dead During Crash (retrospective)

> **Implementation status:** 🟡 Partial.
>
> The **retrospective alert mechanic** (alert_type `retrospective` → 300s countdown → SES on
> expiry) is implemented in alert-handler and Step Functions, and processing-engine degrades
> delayed/unknown crashes to `retrospective`. The **device-layer parts** of this flow —
> helmet detecting the dead phone, buffering crash + surrounding telemetry, phone revival
> triggering catch-up sync — are design intent only (phone-dead buffering is not simulated).

### Implemented: retrospective alert handling

```
[processing-engine] → [SQS Alert Queue]  : alert_type=retrospective (no telemetry found in Hot Storage)
[alert-handler] → [Execution Registry]   : acquire lease (status STD_CD path, wait 300s)
[alert-handler] → [AWS Step Functions]   : StartExecution(wait 300s)
[alert-handler] → [AWS IoT Core]         : publish notification (persistent)
[alert-handler] → [SQS Alert Queue]      : delete
```

After 300s: lease still STD_CD-owned → `ConfirmIncident` → SES alert. If rider cancels →
`INCIDENT_CANCELLED`. If the lease was stolen → `SilentExit`.

> **Note (corrected):** The original design described a rider-facing **confirm** action
> ("Crash detected — alert emergency services?") as a required gate before alerting.
> **Not implemented.** There is no `CONFIRM` override action in `handle_override`; the
> retrospective flow auto-fires on timeout. This is captured as a Future Enhancement.

### Design only: phone-dead device behaviour

- Helmet stores crash event + surrounding telemetry in local buffer when phone is dead.
- On phone revival, the normal startup + catch-up sync runs; buffered data (incl. crash
  event) is uploaded and treated as regular telemetry; crash flag triggers the crash queue.

---

## Flow 5 — Retrospective Alert After Phone Revival

> **Implementation status:** 🟡 Partial — absorbed into Flow 4.

The retrospective trigger, validation cases, notification, and delivery chain are the same
regardless of why the crash event was delayed. See Flow 4. The rider-confirm gate remains a
Future Enhancement.

---

## Flow 6 — Graceful Shutdown & Device Lifecycle

> **Implementation status:** 🟡 Partial.
>
> The **cloud-side lifecycle** (Device Status Table + LWT disambiguation) is implemented.
> The device-side ack chain and post-shutdown rider choice flows are design intent.

### Implemented: helmet lifecycle via Control Queue

The simulator publishes **ONLINE** on connect and **GRACEFUL_SHUTDOWN** on clean exit
(menu option 6 or Ctrl+C) to `helmet/{id}/control` (not directly to DynamoDB).

```
[Simulator] → [AWS IoT Core]            : helmet/{id}/control {status: ONLINE          } : on connect
[Simulator] → [AWS IoT Core]            : helmet/{id}/control {status: GRACEFUL_SHUTDOWN} : on clean exit
[AWS IoT Core] → [SQS Control Queue]    : control message (via iot_control_rule)
[processing-engine] → [SQS Control Queue]: read control message
[processing-engine] → [Device Status]   : ONLINE      → {status: ONLINE,      connected_at,   TTL 900s}
                                       : GRACEFUL_SHUTDOWN → {status: GRACEFUL_SHUTDOWN, shutdown_timestamp, TTL 900s}
```

**Answer to direct questions we get about this flow:**

- **The Control Queue exists** (`smart-helmet-control-queue`) and is wired via
  `iot_control_rule` (`SELECT * FROM 'helmet/+/control'`). It is the *only* ingress for
  lifecycle messages today.
- **Graceful shutdown is not written directly** to the Device Status Table — it passes
  through IoT Core → Control Queue → processing-engine, which performs the write.
- **Device Status Table rows have a TTL** of 900 seconds (set on `TimeToExist`); rows are
  also auto-expired by DynamoDB TTL as a safety net. If no wrapper exists, the last known
  ONLINE/GRACEFUL_SHUTDOWN is forgotten after 15 minutes.

### Design only: riding-session acknowledgement and rider-choice flows

The original design included a full ack chain (cloud confirms shutdown → helmet powers
down), a 10-second power-down timer, and post-shutdown rider choices (notify emergency
services anyway / rider is safe). These are **not implemented** — the simulator disconnects
immediately after publishing GRACEFUL_SHUTDOWN and the LWT fires, which the cloud treats as
an expected offline event *only if* the shutdown record is still fresh.

---

## Flow 7 — Battery Death

> **Implementation status:** 🔴 Design only.

No battery-level monitoring exists in the simulator or the cloud services. The design
intent (10% low-battery warning → 5% shutdown message with last telemetry, classification by
last telemetry when battery dies) is captured for future firmware/app work. Note: the SSM
parameter set includes `lwt_grace_period_seconds` (900s), which the cloud uses to
disambiguate LWT after a graceful shutdown — battery levels themselves play no role in the
cloud logic today.

---

## Flow 8 — Unexpected Dropout / LWT

> **Implementation status:** ✅ Implemented (corrected).
>
> This is the LWT disambiguation flow. It is much simpler and more fail-safe than the
> original design, and the data flow doc has been corrected to match.

**Key correction — we do NOT check last telemetry for an LWT.** The LWT itself *is* the
signal: the helmet vanished without warning. The assumption is the helmet may have been
destroyed and never got a chance to publish anything. So we do not query Hot Storage and do
not look for a crash flag. We only ask one question: *did this helmet gracefully shut down
recently?* If not → treat as a genuine dropout and start an alert.

```
[AWS IoT Core] → [SQS LWT Queue]         : LWT message (helmet/{id}/lwt)       : on unexpected disconnect
[processing-engine] → [SQS LWT Queue]    : read LWT                            : event-driven
[processing-engine] → [Device Status]    : get_item(helmetId)                  : immediately
[processing-engine] → [SSM]              : lwt_grace_period_seconds (default 900s)
[processing-engine] → [processing-engine] : is_graceful =
                                            status==GRACEFUL_SHUTDOWN AND now - shutdown_timestamp < grace
   Branch A — graceful shutdown recent   → log "LWT ignored", delete message, NO alert
   Branch B — otherwise (genuine dropout) → send crash alert to Alert Queue:
                                            alert_type = STD_CD (30s countdown)
                                            incident_id = uuid5(helmet:ts:LWT)
                                            location = "Unknown"
```

- **Grace period:** 900 seconds (SSM `lwt_grace_period_seconds`) — NOT the 5 seconds in the
  original design.
- **No 5-second reconnection grace timer** is implemented; the LWT is evaluated once when it
  is dequeued.
- **Alert type:** `STD_CD` → the standard 30-second countdown runs (smartphone carries it;
  rider can cancel). If no cancellation, the alert fires and reaches the configured SES
  address.
- **No crash-flag / last-telemetry validation.** This is the fail-safe posture: a lost
  signal defaults to help, not to silence.

---

## Flow 9 — Infrastructure Failure, Monitoring & Mass Alerts

> **Implementation status:** Monitor & alarm layer 🟡/✅ partial; mass-alert decision tree 🔴
> design only.

### Flow 9A — Monitoring Stack and Detection

> **Implementation status:** ✅ Implemented (corrected).
>
> Monitoring is **CloudWatch-native**, not Prometheus/Grafana. All alarms fan out to a single
> SNS topic whose only subscription is an email. There is no PagerDuty, no Prometheus, no
> Alertmanager, no Grafana, no Healthchecks.io dead-man's switch in the codebase.

**Registry / stack (as implemented):**

| Source | Metric | Alarm |
|---|---|---|
| SQS | DLQ depth (`ApproximateNumberOfMessagesVisible`) > 0 | per-queue (6 DLQs) |
| SQS | Oldest message age > 600s | per-queue (6 queues) |
| DynamoDB | ReadThrottleEvents + WriteThrottleEvents > 0 | per-table (hot, cold, execution registry) |
| IoT Core | `RuleMessageThrottled` > 0 | single |
| Step Functions | `ExecutionsFailed` + `ExecutionsTimedOut` > 0 | on the alert state machine |
| CloudWatch Logs | `ERROR` in ECS log stream filtered > 5/min | single |
| ECS | cluster memory utilization > 90% | single |

```
<metric breach> → CloudWatch alarm → SNS (smart-helmet-infra-monitoring-alerts-topic)
                                  → email subscription (configured address)
```

| Failure Type | Notified Via | Recipient |
|---|---|---|
| Any DLQ non-empty | CloudWatch → SNS | email |
| DynamoDB / IoT / SFN throttling & failures | CloudWatch → SNS | email |
| SQS message ageing / app errors / cluster memory | CloudWatch → SNS | email |

**What is NOT implemented and remains design intent:**
- Prometheus scrape of `/health` endpoints; Alertmanager routing; Grafana dashboard.
- PagerDuty paging; escalation of any kind.
- Healthchecks.io dead-man's switch (external monitor of the monitoring stack).
- Fleet-wide device buffer-depth monitoring.
- Mass-alert threshold detection and the geographic/firmware decision tree
  (see design-only 9B–9K below).

> **Recommendation:** for this project, CloudWatch-native monitoring is sufficient, cheaper,
> and has zero extra operational surface. A Prometheus/Grafana stack is a Future Enhancement
> if you want to demonstrate multi-tool observability.

### Flow 9B — Sensor Failure

> **Implementation status:** 🔴 Design only (fleet-wide part). Single-helmet false positives
> are covered by Flow 3.

Single-helmet sensor failure is caught by processing-engine's false-positive validation
(`FP_CD`). **Fleet-wide** sensor failure (a firmware bug causing a burst of false crash
flags) with hold/release and mass-alert triage is **not implemented** — no firmware-version
field, no mass-alert decision tree, no hold mechanism. Design intent retained.

### Flow 9C — Helmet Telemetry to Smartphone Failure

> **Implementation status:** 🔴 Design only.

Requires device-layer Bluetooth failure detection, `helmet/{id}/bluetooth_disconnected`
topic, and catch-up sync — none provisioned or implemented. Design intent retained.

### Flow 9D — Smartphone Telemetry to Cloud Failure

> **Implementation status:** 🔴 Design only.

Covers device-layer internet/broker/app failures; no new infrastructure behaviour. See
Flow 2 Design Annex for the buffering/catch-up design.

### Flow 9E — IoT Core / MQTT Broker Failure

> **Implementation status:** 🔴 Design only.

If IoT Core is down, LWT cannot fire (known limitation — correct as stated). Detection via
CloudWatch IoT Core alarm → SNS (implemented). Rider `infra/status` topic notifications and
catch-up sync are design intent (topic not provisioned).

### Flow 9F — Telemetry Infrastructure Failure

> **Implementation status:** 🔴 Design only.

The queue-decoupling principle (Telemetry Queue buffers incoming batches; processing-engine
drains what already landed; SQS retention holds the rest) is accurate, and SQS is the
shock absorber. Prometheus health checks, `infra/status` topic rider notifications, and
dedicated recovery logic are design intent.

### Flow 9G — Processing Infrastructure Failure

> **Implementation status:** 🔴 Design only.

Crash/Control/LWT events accumulate in their SQS queues (14-day retention) during an
outage and are drained on recovery by the plain poll loop. The documented queue-drain order
(Control → LWT → Crash), the 24h/14d branch logic, and DLQ behaviour are design reasoning,
not separate recovery code. The implemented recovery is simply *SQS retention +
reprocessing*.

### Flow 9H — Alerting Infrastructure Failure

> **Implementation status:** 🔴 Design only, with one implemented principle.

The principle that **Step Functions continues running independently of alert-handler** is
correct and implemented — the countdown timer, IoT publishes, and audit writes live in the
ASL, so an alert-handler outage does not stop active countdowns. New alert events queue in
SQS (14-day retention) until recovery. Prometheus health checks, infra/status notifications,
and DLQ monitoring-alarm wiring are design intent (the DLQ alarm itself is implemented).

### Flow 9I — Database Failure

> **Implementation status:** 🔴 Design only.

The two failure modes (Hot Storage outage → all crashes degrade to retrospective; Cold
Storage outage → no contact/audit writes) are accurate reasoning. **No replication or
failover is implemented** — DynamoDB tables are single provisioned tables. Known limitations
below (see Known Limitations).

### Flow 9J — Parameter Store Unavailability

> **Implementation status:** 🟡 Partial.

- ✅ Implemented: **cold-start fallback** — `get_ssm_parameter(name, default)` in both
  processing-engine and alert-handler returns a hardcoded default if SSM is unavailable, so
  services never block on Parameter Store.
- ❌ Not implemented: the 5-minute cache-refresh cycle (services fetch per call),
  Prometheus health check, rider "degraded" notifications.

### Flow 9K — Bad Firmware Update

> **Implementation status:** 🔴 Design only.

No firmware pipeline (no AWS IoT Device Management, no canary jobs, no rollback, no S3
firmware storage, no firmware-version field). Full design intent retained; see Future
Enhancements.

### Flow 9L — Bad Infrastructure Deploy — CI/CD

> **Implementation status:** 🟡 Partial.

- ✅ Implemented (actually the strongest part of the platform): CI/CD path-filtered
  workflows; `terraform validate` + `plan` before `apply`; `aws-actions` ECS
  render/deploy-task-definition with rolling updates gated by health-check readiness; SQS
  visibility/retry semantics protect queue consumers; `lifecycle.ignore_changes =
  [task_definition]` lets pipelines swap images without Terraform fighting them.
- ❌ Not implemented / design intent: PagerDuty monitoring of failed deployments; database
  migration safety; a "half-baked state" recovery runbook beyond re-applying the reverted
  commit.

### Flow 9M — Monitoring Stack Failure

> **Implementation status:** 🔴 Design only.

There is no separate monitoring stack to fail; monitoring is CloudWatch-native (AWS-managed).
The **dead-man's switch** idea (an external service expecting a heartbeat from the
monitoring setup, e.g. Healthchecks.io) is a valid Future Enhancement — but "watch the
watchers" via CloudWatch means adding an out-of-band check that the SNS/email alarms are
still being produced.

---

## Flow 10 — Firmware Update

> **Implementation status:** 🔴 Design only.

No firmware pipeline is implemented. The design (canary rollout via AWS IoT Device
Management, OTA delivery through IoT Core → smartphone → helmet, staging + install on next
power cycle, abort criteria, rollback) is retained as design intent and Future Enhancement.
It is orthogonal to the alert platform.

---

## Flow 11 — Scale Up / Scale Down

> **Implementation status:** 🟡 Partial — corrected to match Terraform.

**Actual configuration (`services/*/infra/autoscaling.tf`):**

| Component | Scaling | Min | Max |
|---|---|---|---|
| telemetry-processor | target-tracking on Telemetry Queue depth | 1 | 3 |
| processing-engine | target-tracking on Crash / LWT / Control queue depth | 1 | 3 |
| alert-handler | target-tracking on Alert / Override queue depth | 1 | 3 |

- Auto-scaling is **reactive target-tracking only** (queue depth), driven by CloudWatch; there
  is **no scheduled scaling, no ALB**, and min/max are 1/3, not 2/5.
- Hot/Cold Storage are **provisioned-capacity** DynamoDB tables (5/5 RCU/WCU,
  device-status 3/3); **no DynamoDB auto-scaling** is configured.
- ECS services use **rolling deployments** with health-check readiness; queue consumers use
  the standard SQS visibility-timeout safety net; SIGTERM handlers stop SQS polling and
  finish in-flight messages (graceful shutdown) — all implemented.

**Design intent (not implemented):** scheduled scaling, ALB in front of a telemetry HTTP
ingest, min 2 / max 5, cooldown periods, CPU-based scaling, ALB connection draining,
DynamoDB auto-scaling. See Future Enhancements.

**Recommended production posture:** for a portfolio/demo project the reactive 1–3 model is
fine. If you later want to demonstrate richer scaling, add scheduled actions and increase min
capacity to 2.

---

## Known Limitations

Consolidated from all flows (accepted for this project, with mitigation ideas in Future
Enhancements):

1. **No database replication / failover.** Single provisioned tables; a Hot or Cold Storage
   outage has no automatic promotion path.
2. **Audit trail gap on Cold Storage failure.** Failed writes during an outage are not
   replayed.
3. **Telemetry data loss during Hot Storage failure.** Live telemetry is fire-and-forget
   with no per-batch ack and no write-layer retry queue.
4. **All crashes degrade to retrospective during a Hot Storage outage** (no in-memory recent
   telemetry cache to validate against).
5. **No rider-facing "confirm" action** for retrospective alerts — auto-fire on timeout is
   the implemented default (see Future Enhancement: retrospective confirm gate).
6. **LWT grace is 900s and static** — controlled via one SSM parameter; no adaptive behavior.
7. **Alert dispatch is a single SES email to a fixed address** — no per-helmet emergency
   contacts, no next-of-kin split, no channel retries/outcome logging.
8. **No mass-alert / firmware-anomaly detection** — a firmware bug or fleet-wide sensor
   failure would fire normal per-helmet alerts.
9. **No external monitor of CloudWatch itself** — if SNS/email delivery silently stops,
   nobody is paged out-of-band.
10. **Control Queue carries only lifecycle messages** (ONLINE / GRACEFUL_SHUTDOWN) today;
    design intended it to also carry low-battery warnings.
11. **Device-layer buffering/catch-up, Bluetooth, battery thresholds** are not simulated or
    implemented; they are design intent for a future device SDK.
12. **Scaling is reactive only (1–3)**, so a true mass event could saturate the consumers
    before target-tracking reacts.

---

## Future Enhancements (Post-MVP)

**Monitoring & observability**
- Prometheus + Alertmanager + Grafana on ECS: scrape `/health` + app metrics, richer
  dashboards, deduplicated alert routing.
- PagerDuty (or similar) integration for the CloudWatch→SNS→paging path.
- Dead-man's switch: an external uptime service expecting a heartbeat ping, alerting
  out-of-band if CloudWatch/SNS stops producing.

**Alerting**
- **Retrospective confirm gate (PO call):** for `retrospective` alerts, ask the rider first
  ("Crash detected at [time]. Alert emergency services?") within the 300s window. Rider
  taps YES → start a fresh 30s STD_CD countdown; NO/no response → log, no alert. Currently
  the auto-fire-on-timeout default is implemented.
- Per-helmet emergency-contact lookup from Cold Storage; split delivery to next of kin &
  emergency services; per-channel retries and delivery-outcome audit logging.
- Delayed-event downgrade check in alert-handler (standard events that sit in the queue
  beyond a threshold become retrospective).

**Device layer**
- Circular buffer for helmet/smartphone local storage to avoid stalls on full buffer.
- Fleet-wide buffer-depth monitoring to detect systemic outages before devices hit limits.
- Battery-level monitoring (10% / 5%) with parameter-driven thresholds.

**Scaling & ingestion**
- Scheduled scaling for commuter rush hours.
- ALB in front of a telemetry HTTP ingest path (with connection draining) if telemetry moves
  from SQS-pull to HTTP-push.
- Min 2 instances for redundancy; CPU-based scaling; DynamoDB auto-scaling (on-demand or
  RCU/WCU target tracking) for Hot Storage.

**Infrastructure resilience**
- Write-ahead logging (WAL) for Cold Storage: log writes to a dedicated SQS queue first,
  drain to DynamoDB when healthy.
- Database replication/standby (read replica or cross-AZ).
- Telemetry write-layer retry queue to eliminate data loss during Hot Storage outages.
- In-memory recent-telemetry cache (e.g. ElastiCache) for crash validation during brief Hot
  Storage outages.

**Firmware / mass-alert**
- Firmware update pipeline (Flow 10): canary rollout, staging on device, install on power
  cycle, abort criteria, rollback — using AWS IoT Device Management + S3.
- Mass-alert detection: count simultaneous crash alerts across the fleet vs a threshold;
  triage geographic clustering vs firmware correctness; hold/release alerts pending Fleet
  Manager / Infrastructure Engineer decision.
- Firmware-version field in telemetry and firmware-anomaly correlation.

**CI/CD**
- Post-deploy regression checking (canary workloads, smoke tests against `/health`) before
  cutting over.
- Scheduled drift detection (`terraform plan` on a timer) to catch state drift early.