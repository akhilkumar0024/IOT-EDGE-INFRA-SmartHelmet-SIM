# ADR-0003: SSM Parameter Store as the cross-stack coupling layer

- **Status:** Accepted
- **Date:** 2026-10-24
- **Deciders:** Akhil Kumar

## Context

The platform is **seven independent Terraform roots**, each with its own state
file: `infra/platform`, `infra/shared-data`, `infra/messaging`,
`infra/monitoring`, and one root per service under `services/<name>/infra`.
They were split out of a single root module so that each layer could be planned,
applied and reverted on its own.

Splitting the state created a problem the monolith did not have: the layers still
have to pass identifiers to each other. The service stacks need the VPC's subnet
and security-group IDs, the cluster name, the execution role ARN, the log group
name, four table names and ARNs, six queue URLs/ARNs/names, two state-machine
ARNs and the incident email address. The monitoring stack needs roughly twenty of
the same identifiers to build its alarms and dashboard.

The constraints that shape the answer:

- **Independent applies.** CI is path-filtered: a change under `infra/messaging`
  must be applicable without touching the service stacks, and vice versa.
- **Least privilege.** A service stack should not be able to read or mutate
  resources that are none of its concern.
- **A clear bootstrap order.** `platform` must exist before anything else;
  `monitoring` resolves parameters at plan time and must be applied last.
- **Single account, single region.** `ap-south-1`, one environment, no
  cross-account access.
- **No extra tooling if the platform already has it.** The stack is already
  using SSM for runtime configuration, so the mechanism exists.

## Decision

Every layer **publishes its outputs** into SSM Parameter Store under a
layer-specific prefix, and consumers resolve them with
`data "aws_ssm_parameter"` at plan time. **No stack reads another stack's remote
state.**

| Prefix | Owner | Parameters | Consumed by |
|---|---|---|---|
| `/smart-helmet/platform/*` | `infra/platform` | 7 | service stacks, monitoring |
| `/smart-helmet/data/*` | `infra/shared-data` | 11 | service stacks, monitoring |
| `/smart-helmet/queues/*` | `infra/messaging` | 24 | service stacks, monitoring |
| `/smart-helmet/config/*` | `infra/shared-data` | 7 | `processing-engine`, `alert-handler` at runtime |
| `/smart-helmet/simulator/*` | `infra/messaging` | 2 (`SecureString`) | the simulator only |

The **parameter name is the contract**. The layer that owns a resource is the
only writer; every other layer is a reader of the names it needs and nothing
more. `ssm_outputs.tf` in each layer is the complete, reviewable list of what
that layer exports.

There are two distinct kinds of consumer, and they are deliberately separate:

- **Terraform, at plan time** — service and monitoring stacks resolve IDs, ARNs,
  URLs and names. The plan/deploy roles hold `ssm:*`/`ssm:GetParameter` on
  `/smart-helmet/*`.
- **Services, at runtime** — `processing-engine` and `alert-handler` read the
  three countdown windows and the LWT grace period with `ssm:GetParameter`,
  scoped to `/smart-helmet/config/*` only. Each read has a hardcoded fallback,
  so a throttled or unavailable Parameter Store degrades the window rather than
  stopping the service.

The two simulator certificate values are the one departure: they are
`SecureString`, because they are secrets rather than identifiers, but they use
the same prefix convention.

## Alternatives rejected

| Option | Why rejected |
|---|---|
| **`terraform_remote_state`** | The consumer must know the producer's backend key and hold read access to its state object — so it sees the producer's entire state, not a deliberate contract. Renames surface as state-schema errors rather than a missing parameter, and the dependency direction is inverted. |
| **A single root module** | This was the pre-refactor shape. One state means one blast radius, slow plans, and no way to apply a layer independently; CI could not scope a deploy by path, and a change to monitoring would queue behind a service change. |
| **Hardcoded IDs, ARNs and names** | Couples the code to one account and region, breaks on every recreate, and has no single source of truth. |
| **Committed `terraform output -json` files** | Static, stale by definition, produce merge conflicts, and give the services nothing to read at runtime. |
| **Terragrunt `dependency` blocks** | An extra tool and wrapper layer — and it still ultimately reads remote state, so it inherits the coupling it appears to remove. |
| **A shared "outputs" stack that everything imports** | Still one state and one apply-ordering constraint, and it does not give a narrow, per-consumer contract. |

## Consequences

**Positive**

- Each layer has independent state, apply and CI. The blast radius of a change is one layer.
- The parameter name is a **narrow contract**: a consumer reads exactly the identifiers it needs, not the producer's whole state.
- Missing input fails loudly at plan time (`parameter not found`), which is easier to diagnose than a remote-state schema error.
- The bootstrap order is expressible and documented: platform first, monitoring last.
- Monitoring can discover the whole system read-only, without importing any other state.
- Parameters hold the live values, so a resource recreated with a new ID propagates on the consumer's next apply.

**Negative / accepted**

- **SSM is a second copy of identifiers** alongside Terraform state. A parameter can be edited out of band, so SSM and the resource can drift, and nothing detects it.
- **No referential integrity.** Deleting or renaming a parameter does not fail the producer's apply — it breaks every consumer at *its* next plan.
- **Cross-layer changes need a coordinated order** (producer applied before consumer). CI encodes this by path filters and documentation, not by a dependency graph.
- **The 51 parameters are a manual inventory.** There is no schema, registry or generated index; `ssm_outputs.tf` files are the inventory, kept correct by review.
- **Plan-time resolution means a mid-run change is missed.** A value changed in SSM between `terraform plan` and `apply` is not seen by an already-planned run.
- **Runtime reads are outside Terraform's view.** A service can read a parameter that no stack publishes; the hardcoded fallback is what stops that from being fatal, and it also hides the mistake.
- **Names carry no environment or region segment**, which is correct for one environment and would collide the moment a second one exists.

**Residual risk + mitigation**

- *Risk:* someone edits a parameter in the console, and the running system diverges from the code. *Mitigation:* every parameter is Terraform-managed, so `plan` reports the drift on the next run; CI is the only writer, and the deploy roles are the only principals with `ssm:*` on the prefix.
- *Risk:* a parameter is deleted while consumers still reference it, breaking their plan. *Mitigation:* deletion is a deliberate Terraform change; the failure is loud, at plan time, and names the missing parameter.
- *Risk:* a new consumer forgets its `ssm:GetParameter` grant and fails with AccessDenied. *Mitigation:* the plan role covers the whole prefix; task roles are scoped to `/smart-helmet/config/*`, which is the only runtime prefix.
- *Risk:* multi-environment collision (the names have no `{env}`). *Mitigation:* not applicable until multi-environment lands — see the reopen conditions.

## Revisit if

- Multi-environment or multi-region is introduced, at which point the names become `/smart-helmet/{env}/...` and region-qualified.
- Cross-account access appears, which SSM parameters cannot satisfy as directly as a shared state or an API.
- A consumer needs several parameters to change together (SSM has no transaction across parameters).
- The parameter count grows past what a human can inventory from the `ssm_outputs.tf` files.
- A dependency graph becomes available to CI (for example Terragrunt), making the apply order enforceable rather than documented.

## References

- `infra/platform/ssm_outputs.tf` — VPC, subnets, security group, cluster, execution role, log group
- `infra/shared-data/ssm_outputs.tf` — tables, state machines, SES topic
- `infra/shared-data/parameters.tf` — the seven business thresholds
- `infra/messaging/ssm_outputs.tf` — queue URLs, ARNs, names and DLQ names
- `infra/messaging/iot_core.tf` — the two simulator certificate parameters
- `infra/monitoring/data.tf` — the read-only discovery side
- `services/*/infra/data.tf` — the per-service plan-time contract
- `services/*/src/main.py` — `get_ssm_parameter` and the runtime fallbacks
- `README.md` §6 — the published SSM contract
- `infra/*/backend.tf` — the seven independent state keys this decision exists to decouple
