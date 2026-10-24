# ADR-0005: Hot/cold DynamoDB split, a one-row lease, and late-cancel reconciliation

- **Status:** Accepted
- **Date:** 2026-10-24
- **Deciders:** Akhil Kumar

## Context

The three ECS services consume **standard** SQS queues, so delivery is
**at-least-once** and unordered. Two consequences shape this decision:

1. **Two kinds of data with opposite lifetimes.** The raw telemetry that
   justified an alert is only useful around the impact and must not be retained.
   The incident record is the durable audit trail and must outlive every
   retention window.
2. **A message can arrive twice, out of order, or late.** A duplicate must not
   produce a second alert, and a rider's cancel that loses the race with the
   countdown must not simply vanish.

The countdown is not a request: it is a Step Functions `Wait` that wakes 5, 30
or 300 seconds later, independent of any container. Between the crash and the
wake, the rider can cancel on a different queue, handled by a different poll
loop. The two paths can race — the timer can confirm an incident in the same
instant the cancel is being dequeued, or a cancel can sit in the queue long
enough for the countdown to expire before it is read.

There is no lock service (no Redis, no ZooKeeper) and no relational database in
the architecture. Whatever mutual exclusion is needed has to come from DynamoDB's
conditional writes.

## Decision

### 1. Two tables with opposite lifetimes

| Table | Key | Writer | TTL | Purpose |
|---|---|---|---|---|
| `smart-helmet-hot-storage` | `helmetId` + `timestamp` | `telemetry-processor` | 24 h | Raw telemetry batches; the evidence a crash is validated against |
| `smart-helmet-cold-storage` | `helmetId` + `timestamp` | Step Functions | none | Durable incident record, one row per incident |

Hot storage answers *"what happened just before impact?"* for at most the
15-second query window, then expires. Cold storage answers *"what did we decide,
and when?"* forever. They are separate tables because their lifetimes, write
volumes and access patterns are opposite: hot takes every batch at high velocity,
cold takes only incidents and is read rarely.

`processing-engine` queries hot storage for `[t-15s, t]`. If no rows are found,
the crash is degraded to `retrospective` rather than guessed at.

### 2. One row per helmet is the lease

`smart-helmet-execution-registry` is keyed by `helmetId` alone. That single row
is the **lease**: at most one incident can own a helmet at a time.

| Field | Role |
|---|---|
| `ownerIncidentId` | **the ownership token** — not the execution ARN |
| `status` | `INITIALIZING` → `STD_CD` / `FP_CD` → `CONFIRMED` / `CANCELLED` / `FALSE_POSITIVE_DISMISSED` |
| `incidentTimestamp` | ordering: a newer incident may take a stale lease |
| `serverDeadline` | server time (`start + wait`); the only clock used to judge an in-window cancel |
| `TimeToExist` | `serverDeadline + 86400` — a crashed workflow cannot leave a helmet leased forever |

`acquire_lease` never reads-then-writes. It writes the row with a condition:

- no row → `attribute_not_exists(helmetId)`
- row held by an older incident → `ownerIncidentId = :owner AND incidentTimestamp = :ts`, and only if the new `incidentTimestamp` is newer
- FP→STD upgrade → `ownerIncidentId = :owner AND status = FP_CD`

The countdown workflow re-reads the lease when it wakes and acts only if
`ownerIncidentId` still equals its own `incident_id`. Every write is conditional
on the same pair. Losing the condition means another actor already resolved the
incident — a normal outcome — so the state machine catches
`ConditionalCheckFailedException` and routes to `SilentExit`.

Nothing calls `StopExecution`. The workflow runs to completion and decides from
the lease, so there is no window in which a process can stop a timer it no longer
owns.

Idempotency has two layers: `incident_id` is deterministic
(`uuid5(helmet, timestamp, location, speed)`), and the Step Functions execution is
named after it, so a duplicate `StartExecution` is rejected by AWS.

### 3. A late cancel is reconciled, not dropped

`handle_cancel` first tries the in-window path: if an active lease is owned by
the same incident and `now <= serverDeadline`, it flips the lease to `CANCELLED`
conditionally and publishes `DISMISS`.

If no lease is active, the countdown has already finished. The handler looks the
incident up in cold storage by `(helmetId, incident_timestamp)`, checks the
`incidentId` matches, and starts `SmartHelmetReconciliationWorkflow` named
`reconcile-<incident_id>`. The predicate is computed in the handler:

```python
"is_reconcilable": 0 <= now - float(incident_timestamp) <= 300
```

The workflow's `MarkResolved` updates cold storage **only** from
`INCIDENT_CONFIRMED` to `RESOLVED_BY_LATE_CANCEL`; a duplicate or racing
reconciliation loses the conditional write and exits silently.

> **Known gap — rider-intent bound.** The original design also required
> `cancel_ts - incident_ts < window`, so that a cancel pressed *after* the
> countdown expired would not retract an escalation. That bound is not
> implemented: the predicate is crash-age only, so any cancel delivered within
> 300 seconds of the crash is honoured. This ADR records the current behaviour;
> it is flagged here for review rather than endorsed, and is tracked in the
> project backlog.

## Alternatives rejected

| Option | Why rejected |
|---|---|
| **One table for hot and cold** | The two have opposite lifetimes. Sharing a table forces either the audit record to expire with the telemetry or the raw telemetry to be retained forever; both would defeat the point. It also merges a high-write stream with a low-write record. |
| **Execution ARN as the ownership token + `StopExecution`** | The original design used this and it was corrected. An execution cannot atomically claim a helmet, and stopping one does not fence a concurrent writer: the older workflow could still write. `ownerIncidentId` + conditional writes makes ownership explicit and race-free. |
| **Read-then-write lease acquisition** | Time-of-check/time-of-use: two consumers can both read "no lease" and both write. The conditional `put_item` is the only atomic claim available without a new service. |
| **FIFO queues to impose ordering** | Arrival order is not the real ordering key — incident timestamps are. FIFO would add throughput ceilings and message-group management to solve a problem the timestamp comparison already solves. |
| **Drop a cancel that arrives after the countdown** | Silently ignores a rider who did press cancel; the whole point of the reconciliation path is not to lose that intent. |
| **Reconcile inline in `alert-handler` instead of a state machine** | The handler is a poll loop; it cannot durably retry an SES send or hold the conditional write across a restart. A Standard execution gives retries, an independent alarm and the execution-name idempotency guard. |
| **Reuse the alert workflow for reconciliation** | It acts on cold storage and on a different trigger (a late message, not a timer), and the two outcome vocabularies would interleave in one definition. A separate machine keeps each end-state write in one place. |
| **On-demand DynamoDB capacity** | The tables are deliberately small and predictable (5/5 RCU/WCU, device-status 3/3). Provisioned capacity is the cheaper choice at simulator volumes; the split would still be required either way. |

## Consequences

**Positive**

- Hot telemetry expires automatically; the incident record is durable and storage cost stays bounded.
- One active alert per helmet is enforced without a lock service.
- Duplicate, out-of-order and late messages are absorbed: deterministic `incident_id`, execution-name uniqueness, and conditional writes.
- A rider's timely cancel is honoured even when it loses the race with the timer.
- The lease TTL means a crashed workflow cannot strand a helmet permanently.
- Reconciliation is idempotent and independently alarmed.

**Negative / accepted**

- **Two consistency domains.** A cold-storage write that fails after `ConfirmIncident` leaves a confirmed lease with no audit row; there is no replay queue. The execution fails and alarms, but the missing row needs a human.
- **Hot storage expires after 24 h**, so a crash delivered later than that degrades to `retrospective` — a deliberate, but real, loss of validation evidence.
- **Cold storage keeps the final state, not history.** It is one row per `(helmetId, timestamp)`: a late FP override reclassifies `FALSE_POSITIVE_DISMISSED` to `INCIDENT_CONFIRMED`, and a late cancel overwrites the row. There is no append-only audit log.
- **`is_reconcilable` mixes server `now` with the device crash timestamp**, so a client clock skew above roughly five minutes silently disables reconciliation.
- **The 300-second reconciliation window is a literal** in `alert-handler`, not an SSM parameter — the only one of the four windows not configurable.
- **The rider-intent bound is absent** (the known gap above): a cancel pressed after the window is still honoured if delivered within 300 seconds.
- **A late cancel does not publish `DISMISS`**, so the helmet HUD is not cleared on the 1B path.
- **Provisioned capacity is sized for the simulator** (5/5, 3/3) and is not autoscaled.

**Residual risk + mitigation**

- *Risk:* a newer incident takes a stale lease and the older workflow exits without acting. *Mitigation:* that is the intended resolution — the older incident is stale by timestamp; the workflow's silent exit is correct, not a failure.
- *Risk:* a cold-storage write fails after confirmation, leaving no audit row. *Mitigation:* the state-machine failure alarm fires, and point-in-time recovery on the table allows the row to be recreated within the 35-day window.
- *Risk:* clock skew disables reconciliation. *Mitigation:* documented; the in-window cancel path uses `serverDeadline` (server clock), so the common case is unaffected.
- *Risk:* the known rider-intent gap lets a late cancel retract an escalation. *Mitigation:* the outer 300-second bound limits it to cancels delivered within five minutes of the crash; the gap is recorded for review.
- *Risk:* the lease TTL (`deadline + 24 h`) expires mid-incident. *Mitigation:* countdown windows are at most 300 seconds, so the TTL is far beyond any legitimate execution.

## Revisit if

- The rider-intent bound is restored, or the reconciliation window is moved to SSM.
- Cold storage needs append-only history rather than one-row-per-incident.
- Hot retention must exceed 24 hours, or the validation window grows beyond 15 seconds.
- Volume makes provisioned capacity the wrong model, or on-demand becomes cheaper.
- A second environment or another region is introduced, which would make the lease region- and environment-aware.
- Device clocks become trusted enough to base more logic on them, or distrusted enough to remove the remaining dependence.

## References

- `infra/shared-data/dynamodb.tf` — the four tables, TTLs and point-in-time recovery
- `infra/shared-data/step_functions.tf` — both state machines and every conditional write
- `services/alert-handler/src/main.py` — lease acquisition, cancel, override and reconciliation predicate
- `services/processing-engine/src/main.py` — hot-storage validation window and classification
- `docs/DATA-FLOW.md` — queue topology and delivery guarantees
- `docs/STEP-FUNCTIONS.md` — workflow states and the lease contract
- `docs/SCENARIO-MATRIX.md` — every incident path and the guarded transitions
- `Research-phase/Alert_Infra_design.md` §1B — the original late-cancel design
