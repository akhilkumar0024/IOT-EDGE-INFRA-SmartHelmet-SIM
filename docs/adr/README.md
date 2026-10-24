# Architecture Decision Records (ADRs)

An **ADR** is a short document that records *why* a significant technical decision was made.
It captures the reasoning, the alternatives that were rejected, and the consequences that were
accepted — none of which are visible by reading the code.

A decision that looks questionable from the outside (e.g. "why are the ECS tasks in public
subnets?") is usually a deliberate trade-off. Without an ADR, a reviewer can only assume it was
an oversight. With one, it becomes evidence of engineering judgement.

## Format

Each ADR lives in its own file: `NNNN-short-title.md`, and follows:

**Context → Decision → Alternatives rejected → Consequences → Revisit if**

Statuses: `Proposed` · `Accepted` · `Superseded by ADR-NNNN` · `Deprecated`

## Index

| ADR | Title | Status |
|---|---|---|
| [0001](0001-public-subnets-and-gateway-endpoints.md) | Public subnets + ingress-free SG + free gateway endpoints only | Accepted |
| 0002 | Terraform split into platform / shared-data / messaging / monitoring + per-service stacks | *to write* |
| [0003](0003-ssm-as-the-cross-stack-coupling-layer.md) | SSM Parameter Store as the cross-stack coupling layer | Accepted |
| 0004 | One SQS queue per signal type, each with a DLQ | *to write* |
| [0005](0005-hot-cold-split-and-late-cancel-reconciliation.md) | Hot/cold DynamoDB split + reconciliation workflow for late cancels | Accepted |
| 0006 | CloudWatch for observability (no Prometheus/Grafana) | *to write* |
| 0007 | Single-environment deployment | *to write* |
| 0008 | Manual approval vs automatic confirmation on the alert countdown | *to write* |
| 0009 | GitHub Actions OIDC federation instead of long-lived AWS keys | *to write* |
| 0010 | `desired_count = 2` / `min_capacity = 2` HA baseline and its cost | *to write* |

## Template

```markdown
# ADR-NNNN: <title>

- **Status:** Proposed | Accepted | Superseded by ADR-NNNN
- **Date:** YYYY-MM-DD
- **Deciders:** <name>

## Context

What is the problem, what constraints apply, and what forces are in play?
Include the cost/operational constraints that actually drove the decision.

## Decision

What we decided to do, stated plainly.

## Alternatives rejected

Each option, and the specific reason it was rejected.

## Consequences

**Positive:** what we gain.
**Negative / accepted:** what we knowingly give up.
**Residual risk + mitigation:** what is still exposed, and how we limit it.

## Revisit if

The conditions that would invalidate this decision.
```
