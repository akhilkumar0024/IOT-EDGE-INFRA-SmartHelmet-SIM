# ADR-0004: One SQS queue per signal type, each with a dead-letter queue

- **Status:** Accepted
- **Date:** 2026-10-24
- **Deciders:** Akhil Kumar

## Context

The system carries six distinct signals, produced by different sources and
consumed by different services:

| Signal | Produced by | Consumed by |
|---|---|---|
| Telemetry batches | IoT rule `iot_telemetry_data_rule` | `telemetry-processor` |
| Crash events | `telemetry-processor` | `processing-engine` |
| Control messages (ONLINE / GRACEFUL_SHUTDOWN) | IoT rule `iot_control_rule` | `processing-engine` |
| Last Will and Testament | IoT rule `iot_lwt_rule` | `processing-engine` |
| Validated alerts | `processing-engine` | `alert-handler` |
| Rider overrides (CANCEL / FP_OVERRIDE) | IoT rule `iot_override_alert_rule` | `alert-handler` |

Their traffic shapes are not alike. Telemetry is high-volume and constant;
override is low-volume and user-driven; control and LWT are rare lifecycle
events. A slow consumer in one path must not apply backpressure to another, and
one malformed message must not be able to stall a healthy queue.

The services are pull-based workers with no inbound network path, and the
architecture deliberately contains no Lambda between the broker and the
services. Every hop is a queue.

## Decision

**One standard SQS queue per signal, each with its own standard DLQ**, configured
with a redrive policy at `maxReceiveCount = 3` and a redrive-allow policy back to
its source queue.

The twelve queues are:

| Source | DLQ | Redrive after |
|---|---|---|
| `smart-helmet-telemetry-queue` | `smart-helmet-telemetry-dlq` | 3 receives |
| `smart-helmet-crash-queue` | `smart-helmet-crash-dlq` | 3 receives |
| `smart-helmet-alert-queue` | `smart-helmet-alert-dlq` | 3 receives |
| `smart-helmet-override-queue` | `smart-helmet-override-dlq` | 3 receives |
| `smart-helmet-control-queue` | `smart-helmet-control-dlq` | 3 receives |
| `smart-helmet-lwt-queue` | `smart-helmet-lwt-dlq` | 3 receives |

All twelve are **standard**, not FIFO. Ordering is not taken from arrival order;
it is taken from the incident timestamp, and duplicates are absorbed by the
lease and deterministic identifiers described in ADR-0005.

Each source queue is also the autoscaling input for the service that consumes
it: `telemetry-processor` target-tracks the telemetry queue, `processing-engine`
the crash / control / LWT queues, and `alert-handler` the alert / override
queues. Each DLQ has a depth alarm, and each source queue has an
oldest-message-age alarm.

## Alternatives rejected

| Option | Why rejected |
|---|---|
| **One queue for everything** | Every consumer would have to demultiplex, or services would compete for messages they cannot handle. One poison message could stall unrelated signals, and scaling could not be tied to a single backlog. |
| **IoT rule → SNS → multiple queues** | Every signal here has exactly one consumer. Fan-out would add a topic per signal and a second routing layer to reach the same one queue. |
| **FIFO queues** | Ordering is already resolved by timestamp, and idempotency is explicit. FIFO would add message groups, a throughput ceiling and deduplication to solve a problem the payload already solves. It would also change the scaling model for no gain. |
| **No DLQ** | A poison message would be redelivered until retention expired, with no signal and no way to inspect or replay it. The failure would be silent apart from a flat queue. |
| **One shared DLQ** | Mixes failure domains: a bad telemetry payload and a bad override would be indistinguishable in triage, and one alarm would cover six unrelated causes. |
| **`maxReceiveCount = 1`** | A single transient error — a throttle, a brief DynamoDB blip — would dead-letter a message that would have succeeded on the next attempt. |
| **A very high `maxReceiveCount`** | Delays detection of a genuinely poison message and wastes retries. Three is enough for transient faults and bounded enough to surface the poison. |
| **Lambda between the rule and the queue** | Another failure domain, another deployment, and another thing to alarm on, for a routing hop the rules engine already performs natively. |

## Consequences

**Positive**

- Each service scales on its own backlog and fails independently; a stuck alert path cannot stall telemetry ingest.
- Poison messages are isolated per signal, inspectable, and replayable via the redrive-allow policy once the cause is fixed.
- DLQ depth is an unambiguous alarm: anything above zero is a defect.
- The queue is the backpressure mechanism, which is why the services need no load balancer or inbound path.
- SQS cost is per request and negligible at these volumes.

**Negative / accepted**

- **Twelve queues and six redrive relationships to manage.** A rename touches the queue definition, its SSM outputs, the consuming stack's `data` block and the service's environment.
- **At-least-once delivery**: duplicates are expected by design, and absorbing them is the consumer's responsibility (ADR-0005).
- **No ordering guarantee.** Out-of-order crashes are resolved by comparing timestamps, not by the queue.
- **`maxReceiveCount` counts receives, not time.** A fast-failing message can dead-letter quickly; the default 30-second visibility timeout is what spaces the retries.
- **Malformed messages are deleted, not dead-lettered.** `telemetry-processor` deletes a payload without `helmet_id`, `processing-engine` deletes an invalid crash, and `alert-handler` deletes a malformed alert or override. The DLQ therefore records *processing* failures, not *validation* failures — a known limitation.
- **Retention is left at the SQS default (four days).** It is not configured explicitly.
- **No customer-managed key.** The queues use the default SSE-SQS encryption; a CMK is deferred with the rest of §5.4b.
- **Redrive is a permission, not an automation.** Moving messages back from a DLQ is an operator action.

**Residual risk + mitigation**

- *Risk:* a consumer is down longer than the retention window, losing messages. *Mitigation:* the oldest-message-age alarm fires at 600 seconds — long before the four-day window — and queue depth is on the dashboard.
- *Risk:* a validation failure is invisible because the message was deleted. *Mitigation:* the deletion is logged with the payload; this is accepted as a known limitation and is a candidate for changing to a dead-letter path.
- *Risk:* duplicates cause double alerts. *Mitigation:* the lease, deterministic `incident_id` and execution-name uniqueness in ADR-0005.
- *Risk:* a DLQ fills without anyone noticing. *Mitigation:* one alarm per DLQ plus the alarm-status widget on the dashboard.

## Revisit if

- Strict ordering becomes a hard requirement, which would justify FIFO with a per-helmet message group.
- A signal acquires a second consumer, which would justify SNS fan-out or a separate queue per consumer instead of one queue per signal.
- Throughput approaches standard-queue limits — unlikely at per-helmet volume.
- Retention longer than four days is required, at which point `message_retention_seconds` must be set explicitly.
- CMK encryption is required, which also adds `kms:Decrypt` / `kms:GenerateDataKey` to every producer and consumer.
- A shared triage process or automated redrive is introduced, which would change the DLQ ownership model.

## References

- `infra/messaging/queues.tf` — the six source queues, six DLQs and redrive policies
- `infra/messaging/iot_core.tf` — the four IoT topic rules that target the source queues
- `infra/messaging/ssm_outputs.tf` — queue URLs, ARNs and names published to consumers
- `services/*/infra/autoscaling.tf` — queue-depth target tracking per service
- `services/*/src/main.py` — the poll loops and their error handling
- `infra/monitoring/alarms.tf` — DLQ-depth and oldest-message alarms
- `infra/monitoring/dashboard.tf` — queue and DLQ depth widgets
- `docs/DATA-FLOW.md` §1, §2, §6 — topics, consumers and delivery guarantees
- `docs/SCENARIO-MATRIX.md` §6 — the malformed-message limitation
