# Smart Helmet — IoT Edge Infrastructure & Alerting Platform

An event-driven IoT platform on AWS for smart-helmet telemetry: ingest crash
telemetry from devices, validate it against a rolling window of raw data,
escalate to a human with a cancellable countdown, and reconcile when the rider's
cancel arrives too late.

[![Lint & Static Checks](https://github.com/akhilkumar0024/IOT-EDGE-INFRA-SmartHelmet-SIM/actions/workflows/lint.yaml/badge.svg)](https://github.com/akhilkumar0024/IOT-EDGE-INFRA-SmartHelmet-SIM/actions/workflows/lint.yaml)

**Region:** `ap-south-1` · **Terraform:** 7 independent stacks · **Compute:** ECS
Fargate, 3 services × 2 tasks · **Not present:** NAT gateway, load balancer,
Lambda, Kinesis, RDS.

## Start here

| Document | What it answers |
|---|---|
| [`docs/SCENARIO-MATRIX.md`](docs/SCENARIO-MATRIX.md) | Every incident path end to end, with a diagram per scenario |
| [`docs/DATA-FLOW.md`](docs/DATA-FLOW.md) | Topics → rules → queues → services → storage, and the delivery guarantees |
| [`docs/STEP-FUNCTIONS.md`](docs/STEP-FUNCTIONS.md) | The two state machines, their inputs, and every guarded transition |
| [`docs/NETWORK.md`](docs/NETWORK.md) | VPC layout and why the tasks are in public subnets |
| [`docs/adr/`](docs/adr/) | Why each significant decision was made, and what was rejected |

---

## 1. Architecture

Three layers, each with its own Terraform root and its own state. They are
connected **only** through SSM Parameter Store — no stack reads another's state
file.

```
┌──────────────────────────────────────────────────────────────────────────┐
│ 1. PLATFORM          infra/platform                                      │
│    VPC · 2 public subnets · IGW · gateway endpoints (S3, DynamoDB)       │
│    ECS cluster · log group · task execution role                          │
│    GitHub OIDC provider · 3 IAM roles (plan, deploy, app-deploy)          │
│    Publishes → /smart-helmet/platform/*                                   │
├──────────────────────────────────────────────────────────────────────────┤
│ 2. BACKBONE          infra/shared-data · infra/messaging                 │
│    4 DynamoDB tables · 2 Step Functions · SES topic                       │
│    6 SQS queues + 6 DLQs · 4 IoT topic rules · simulator certificate      │
│    Business thresholds in Parameter Store                                 │
│    Publishes → /smart-helmet/data/* · /smart-helmet/queues/* · /config/*  │
├──────────────────────────────────────────────────────────────────────────┤
│ 3. SERVICES          services/<name>/infra  (one stack per service)      │
│    telemetry-processor  ·  ingests telemetry, writes hot storage          │
│    processing-engine    ·  15s window analysis, classification, LWT       │
│    alert-handler        ·  lease, countdown, cancel and override          │
│    Each with its own ECR repo, task role, task definition, autoscaling    │
├──────────────────────────────────────────────────────────────────────────┤
│ 4. OBSERVABILITY     infra/monitoring                                    │
│    28 CloudWatch alarms · 1 dashboard · IoT Core logging → AWSIotLogsV2   │
│    Discovers everything from SSM — owns no resources of its own           │
└──────────────────────────────────────────────────────────────────────────┘
```

`infra/monitoring` is deliberately last and deliberately read-only with respect
to what it watches: it looks resources up by SSM path, so nothing in the layers
above has to know it exists.

### Request shape

Services are **pull-based workers**, not request handlers. Every hop between
them is an SQS queue, so a slow consumer applies backpressure instead of failing
a request another service is waiting on. That is also why there is no load
balancer and no inbound network path:

```
device ──MQTT──▶ IoT Core ──rule──▶ SQS ──▶ service ──▶ DynamoDB
                    ▲                                        │
                    └────── helmet/<id>/alert/status ◀───────┘
```

---

## 2. Repository layout

```text
.github/workflows/            8 workflows, decoupled by path filter
  infra-platform.yaml            infra/platform/**          → plan on PR, apply on main
  infra-data.yaml                infra/shared-data/**
  infra-messaging.yaml           infra/messaging/**
  infra-monitoring.yaml          infra/monitoring/**
  infra-services.yaml            services/**/infra/**       → matrix over changed services
  svc-telemetry.yaml             services/telemetry-processor/** (excludes infra/)
  svc-processing.yaml            services/processing-engine/**
  svc-alerts.yaml                services/alert-handler/**
  lint.yaml                      no path filter — lints the workflows themselves

infra/
  platform/                    VPC, subnets, endpoints, cluster, IAM, OIDC
  shared-data/                 DynamoDB tables, Step Functions, SSM thresholds
  messaging/                   SQS queues + DLQs, IoT rules, IoT logging
  monitoring/                  alarms and the dashboard, built from SSM lookups

services/<name>/
  src/                         main.py (single poll loop), requirements.txt
  Dockerfile                   non-root uid 10001, unbuffered stdout
  infra/                       ECR repo, task role, task definition, service, autoscaling

simulator/
  helmet_sim.py                interactive client: telemetry, crash, cancel, override, LWT
  load_test.py                 MQTT flood tester

Scripts/
  bootstrapScript.sh           one-time Terraform state backend
  deploy_images.sh             manual image push (bootstrap only — CI is the normal path)

docs/                          architecture and flow documentation, ADRs
Research-phase/                the design work that preceded the implementation
```

The ECS **task definition is not committed**. Terraform creates the initial
revision; the deploy workflow then reads the live definition
(`aws ecs describe-task-definition`), swaps only the image tag, and registers a
new revision. The running service is the source of truth, which is why
`task_definition` sits in the service's `ignore_changes`.

---

## 3. Prerequisites

| Requirement | Notes |
|---|---|
| Terraform ≥ 1.10 | Every backend sets `use_lockfile = true`, and S3-native locking landed in 1.10. The `required_version` in the stacks still says `>= 1.5.0`, which understates it — see *Known gaps*. |
| AWS CLI v2 | With credentials able to create IAM roles, VPCs and DynamoDB tables |
| Docker | Only for local image builds |
| Python 3.11 | Matches the container base image |
| A verified SES identity | The alert and stand-down emails are sent **from** the same address they are sent **to**. If the SES identity is not verified, the Step Functions executions fail. In the SES sandbox the recipient must be verified too. |

### GitHub repository configuration

These are not in the repo and must be set once:

| Kind | Name | Used by |
|---|---|---|
| Variable | `AWS_ACCOUNT_ID` | Every `configure-aws-credentials` step |
| Variable | `AWS_REGION` | Same |
| Variable | `SNS_EMAIL_ADDRESS` | `infra-data` and `infra-monitoring` apply; the Step Functions email |
| Setting | Push protection | Blocks a push containing a supported secret |
| Setting | Branch protection | Not yet enabled — see *Known gaps* |

OIDC means there are **no long-lived AWS keys in GitHub**. Three roles are
created by `infra/platform`, each with a different trust condition:

| Role | Trusted from | Can do |
|---|---|---|
| `smart-helmet-tf-plan-role` | Any ref in this repo | Read-only. Deliberately broad, because PR plans legitimately come from branches |
| `smart-helmet-tf-deploy-role` | `refs/heads/main` only | Apply |
| `smart-helmet-app-deploy-role` | `refs/heads/main` only | Push images, update ECS services |

The deploy roles are pinned to `main` in the **trust policy**, not just in the
workflow. A workflow-level `if:` is convenience; the trust policy holds even if a
new workflow is added on a branch.

---

## 4. Bootstrap order

The order matters. Each step consumes SSM parameters written by an earlier one.

```bash
export AWS_REGION=ap-south-1
EMAIL="you@example.com"

# 1 — State backend (once per account; cannot be Terraform-managed)
bash Scripts/bootstrapScript.sh

# 2 — Platform
cd infra/platform       && terraform init && terraform apply

# 3 — Backbone (shared-data needs the email)
cd ../shared-data       && terraform init && terraform apply -var="sns-email-address=$EMAIL"
cd ../messaging         && terraform init && terraform apply

# 4 — Observability
cd ../monitoring        && terraform init && terraform apply -var="sns-email-address=$EMAIL"

# 5 — Service infrastructure
cd ../../services/telemetry-processor/infra && terraform init && terraform apply
cd ../../processing-engine/infra            && terraform init && terraform apply
cd ../../alert-handler/infra                && terraform init && terraform apply

# 6 — Push a first image for each service, then let CI take over
bash Scripts/deploy_images.sh
```

### Traps in this sequence

1. **The email variable has no default**, and `infra/shared-data` plus
   `infra/monitoring` will not plan without it. Pass `-var="sns-email-address=…"`.

   The environment-variable form works but needs care, because the variable name
   contains a **hyphen**:

   - `export TF_VAR_sns-email-address=…` is a bash **error** — `not a valid identifier`
   - `TF_VAR_sns_email_address=…` (underscore) is accepted by the shell and then
     **silently ignored** by Terraform

   Use `env`, which does not care about shell identifier rules:

   ```bash
   env 'TF_VAR_sns-email-address=you@example.com' terraform apply
   ```

2. **Step 5 creates ECR repositories and ECS services before any image exists.**
   The tasks will start, fail to pull, and cycle until step 6 gives them
   something to pull. This is expected on a first bootstrap, not a broken deploy
   — the circuit breaker will roll the deployment back and the service will sit
   at zero running tasks until the first image lands.

3. **`infra/platform` must be applied before anything else.** It creates the
   VPC, the cluster, the execution role and the OIDC provider that every other
   layer and every workflow depends on.

4. **`infra/monitoring` must be applied last.** It resolves ~20 SSM parameters
   at plan time; if it runs first, the plan fails on missing parameters.

---

## 5. Deployment

### Normal path — CI, on merge to `main`

| You change | Workflow | What happens |
|---|---|---|
| `services/<name>/src/**` | `svc-<name>.yaml` | Build → Trivy image scan → push (`<sha>-<run_number>`, immutable) → render task def → rolling ECS update |
| `services/<name>/infra/**` | `infra-services.yaml` | Terraform plan/apply for that service only, via a matrix over changed paths |
| `infra/<layer>/**` | `infra-<layer>.yaml` | Terraform plan on PR, apply on merge |
| Anything | `lint.yaml` | ruff, pip-audit, hadolint, shellcheck, trivy config, gitleaks, actionlint, yamllint |

Images are tagged `${{ github.sha }}-${{ github.run_number }}` and the ECR
repositories are **immutable** — a tag can never be overwritten, so an ECS
rollback always lands on a real previous image. `:latest` is never pushed,
precisely because "roll back to latest" is a no-op.

### Manual path

`Scripts/deploy_images.sh` pushes images tagged `<sha>-manual-<epoch>`. It only
pushes; it does not deploy. Run it for a first bootstrap, then trigger the
service's workflow or `aws ecs update-service`.

---

## 6. Configuration

Business thresholds live in SSM, not in code, so they change without a deploy:

| Parameter | Default | Effect |
|---|---|---|
| `/smart-helmet/config/standard_alert_window_seconds` | 30 | Countdown before a crash alert is escalated |
| `/smart-helmet/config/false_positive_window_seconds` | 5 | Window in which a rider can say "I'm fine" |
| `/smart-helmet/config/retrospective_alert_window_seconds` | 300 | Countdown when a crash arrives with no telemetry history |
| `/smart-helmet/config/lwt_grace_period_seconds` | 900 | How long after a graceful shutdown a disconnect is still ignored |

Each is read with a hardcoded fallback if Parameter Store is unreachable, so a
throttled SSM call degrades the window rather than killing the service.

**The late-cancel reconciliation window is the exception** — it is a literal
`300` in `alert-handler`. See *Known gaps*.

### The SSM contract

Layers publish their outputs under `/smart-helmet/<layer>/<resource>` and never
reference each other's state:

| Prefix | Published by | Consumed by |
|---|---|---|
| `/smart-helmet/platform/*` | `infra/platform` | service stacks, monitoring |
| `/smart-helmet/data/*` | `infra/shared-data` | service stacks, monitoring |
| `/smart-helmet/queues/*` | `infra/messaging` | service stacks, monitoring |
| `/smart-helmet/config/*` | `infra/shared-data` | `processing-engine`, `alert-handler` |

```bash
aws ssm describe-parameters --query 'Parameters[?starts_with(Name,`/smart-helmet`)].Name' --output text
```

### Resource inventory

| Kind | Names |
|---|---|
| ECS services | `smart-helmet-telemetry-service` · `smart-helmet-processing-service` · `smart-helmet-alerts-service` |
| Task definitions | `smart-helmet-telemetry-task` · `-processing-task` · `-alerts-task` |
| Containers | `telemetry-container` · `processing-container` · `alerts-container` |
| ECR repositories | `smart-helmet-telemetry-service-repo` · `-processing-service-repo` · `-alert-service-repo` |
| SQS queues | `smart-helmet-{telemetry,crash,alert,override,control,lwt}-queue`, each with a matching `-dlq` |
| DynamoDB tables | `smart-helmet-{hot-storage,cold-storage,execution-registry,device-status}` |
| Step Functions | `SmartHelmetAlertWorkflow` · `SmartHelmetReconciliationWorkflow` |
| IoT topic rules | `iot_telemetry_data_rule` · `iot_override_alert_rule` · `iot_lwt_rule` · `iot_control_rule` |
| Log groups | `/ecs/smart-helmet-cluster` · `AWSIotLogsV2` |
| Dashboard | `smart-helmet-observability` |
| Alarms | 28, all prefixed `smart-helmet-` |

---

## 7. Security posture

| Control | Detail |
|---|---|
| Network ingress | **None.** The tasks' security group has no ingress rules at all, so the public IP on each task is an egress mechanism, not an exposure. See [ADR-001](docs/adr/0001-public-subnets-and-gateway-endpoints.md). |
| AWS credentials | OIDC federation; no long-lived keys in GitHub. Apply roles pinned to `main` in the trust policy. |
| Image supply chain | Actions pinned to commit SHAs (Dependabot advances them), images scanned with Trivy before push, ECR repositories immutable. |
| Secrets in git | gitleaks over full history in CI, plus GitHub push protection. |
| Least privilege | Separate roles for Terraform plan, Terraform apply, app deploy, ECS task execution, IoT→SQS, IoT logging, and one task role per service. |
| Encryption at rest | Every store uses AWS-managed keys (DynamoDB, SQS, S3, CloudWatch Logs). No customer-managed KMS keys — an accepted trade-off, recorded in the ADRs. |

Accepted findings are enumerated in [`.trivyignore`](.trivyignore) with the
reason for each, so the file reads as a record of decisions rather than a way to
switch scanning off.

---

## 8. Observability

- **28 CloudWatch alarms** — DLQ depth, SQS oldest-message age, DynamoDB
  throttling, Step Functions failures, IoT Core throttling, application `ERROR`
  volume, ECS service health (tasks below desired, CPU and memory saturation per
  service) and cluster memory.
- **`smart-helmet-observability` dashboard** — ECS health, all 12 queue depths,
  oldest-message age, Step Functions outcomes, IoT Core activity, and an alarm
  status grid.
- **IoT Core logging is enabled** at `INFO`, writing JSON events to
  `AWSIotLogsV2`. This is the only record of what happens *inside* the broker:
  authentication failures, publishes that match no rule, and rule-engine errors.
- **Container Insights** is enabled on the cluster, which is what publishes the
  per-service `RunningTaskCount` / `DesiredTaskCount` metrics the alarms use.

---

## 9. Cost

List prices for `ap-south-1`, computed from the live rate card. Fargate is ~95%
of the total.

**Rates used:** `$0.04256` per vCPU-hour · `$0.004655` per GB-hour ·
`$0.10` per alarm-month.

| State | Tasks | vCPU | Memory | Compute | Alarms | Total |
|---|---|---|---|---|---|---|
| Baseline (min capacity) | 6 | 1.5 | 3 GB | **$56.79** | $2.80 | **≈ $60 / month** |
| Max autoscaling | 14 | 3.5 | 7 GB | **$132.53** | $2.80 | **≈ $135 / month** |

Autoscaling ceilings: telemetry 6, processing 4, alerts 4.

Everything else is per-request and negligible at simulator volumes:

| Service | Charged by |
|---|---|
| SQS | per request — 12 queues, a few thousand requests a month |
| DynamoDB | on-demand, per request + storage |
| Step Functions | $0.025 per 1,000 state transitions |
| IoT Core | per million messages |
| SES | $0.10 per 1,000 emails |
| S3 (state) | 6.6 KB |
| ECR | $0.10 per GB-month |
| CloudWatch Logs | per GB ingested, with 30-day retention on both log groups |
| VPC gateway endpoints | **free** |

**What keeps this small:** no NAT gateway (~$32/month plus data, avoided by
using public subnets with an ingress-free security group), no load balancer, no
RDS, and 30-day log retention on both log groups instead of never-expire.

---

## 10. Teardown

Destroy in reverse order of creation:

```bash
cd services/telemetry-processor/infra && terraform destroy
cd ../../processing-engine/infra      && terraform destroy
cd ../../alert-handler/infra          && terraform destroy
cd ../../../infra/monitoring          && terraform destroy   # needs the email var
cd ../messaging                       && terraform destroy
cd ../shared-data                     && terraform destroy   # needs the email var
cd ../platform                        && terraform destroy
```

Four things survive a clean destroy, and all four are expected:

| Survivor | Why |
|---|---|
| `smarthelmet-terraform-state` (S3) | It is the backend. Deleting it means re-running the bootstrap and losing all state history. |
| `terraform-state-lock` (DynamoDB) | Orphaned. Every backend now uses `use_lockfile = true` (S3-native locking), so this table is unused and safe to delete by hand. |
| `/aws/ecs/containerinsights/<cluster>/performance` (log group) | Created by Container Insights, never owned by Terraform. Safe to delete by hand. |
| The ECS cluster, as `INACTIVE` | `destroy` empties it but leaves the cluster record. `aws ecs delete-cluster --cluster smart-helmet-cluster` removes it. |

**Also worth doing after a teardown:** IoT Core logging is account-level, so it
outlives the infrastructure and will still point at the deleted logging role.
Turn it off with:

```bash
aws iot set-v2-logging-options --disable-all-logs
```

---

## 11. Known gaps

Recorded deliberately rather than discovered later.

- **No branch protection on `main`.** The lint workflow runs on push and is
  therefore advisory; nothing blocks a merge. The `lint.yaml` header says so.
- **No tests.** There is no `tests/` directory and pytest is not a gate. Handler
  logic, the Step Functions definitions and the end-to-end flows are verified by
  hand.
- **The late-cancel window is hardcoded.** `alert-handler` uses a literal `300`
  for `is_reconcilable`, so unlike the other three windows it cannot be changed
  without a deploy.
- **A late cancel does not notify the device.** The reconciliation path sends
  the stand-down email but never publishes `DISMISS` to
  `helmet/<id>/alert/status`, so the rider's HUD is not cleared in that path.
- **Three SSM parameters are provisioned but never read** —
  `unconfirmed_chunk_ttl_hours`, `mass_alert_threshold` and
  `firmware_anomaly_threshold`. They imply features that do not exist yet.
- **No account-level audit trail.** CloudTrail, AWS Config and GuardDuty are not
  enabled at the account level, so there is no record of API activity outside
  what the application logs capture.
- **ECR repository naming is inconsistent.** The alerts image lives in
  `smart-helmet-alert-service-repo` — singular — while the ECS service, the task
  definition family and the container are all `…-alerts…`, plural. It works, but
  it is a trap when scripting against the repository name.
- **`IsReconciliable` vs `is_reconcilable`.** The state name and the input field
  differ by one letter. Renaming either alone silently breaks the Choice.
- **`required_version` understates the real requirement.** All seven backends set
  `use_lockfile = true`, which needs Terraform ≥ 1.10, but every stack still
  declares `>= 1.5.0`. On 1.5–1.9 the backend option is rejected outright.

---

## 12. Design history

The system was designed before it was built: the research and scenario design
ran from March to July 2026, the first Step Functions module landed in June, and
the infrastructure was reorganised into the current stacks in September. The
original hand-drawn scenario sheets and the design notes are kept in
[`Research-phase/`](Research-phase/), and the vocabulary in the implementation
(`STD_CD`, `FP_CD`, `CANCELLED`, `CONFIRMED`) comes directly from them.

See [`docs/adr/`](docs/adr/) for the decisions that shaped the current shape.
