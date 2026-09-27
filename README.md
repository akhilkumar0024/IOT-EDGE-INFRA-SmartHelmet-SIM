# IoT Edge Infrastructure & Smart Helmet Microservices

An enterprise-grade, event-driven IoT microservices platform on AWS for real-time smart helmet telemetry ingestion, crash anomaly validation, automated emergency alerting, and rider override handling.

---

## 🏛 Architecture Overview

The system is organized into a **Decoupled 3-Tier Microservices Architecture**, separating low-churn platform infrastructure, shared event/data backbones, and independent containerized microservices.

```
+---------------------------------------------------------------------------------------+
|                                1. FOUNDATION PLATFORM                                 |
|  - VPC & Public Subnets              - ECS Fargate Cluster Shell                      |
|  - Internet Gateway & VPC Endpoints  - GitHub Actions OIDC Providers & IAM Roles      |
|  - Shared Security Groups            - Shared Task Execution Role                     |
|  (State: platform/terraform.tfstate | Changes: ~Once a year)                          |
+---------------------------------------------------------------------------------------+
                                           |
                                  Publishes via SSM
                                           v
+---------------------------------------------------------------------------------------+
|                             2. SHARED DATA & MESSAGING                                |
|  Data Layer (shared-data/):                          Messaging Layer (messaging/):     |
|   - DynamoDB (Hot, Cold, Execution Registry, Status)  - SQS Queues & Dead Letter Queues|
|   - Step Functions (Emergency & Reconciliation)       - AWS IoT Core MQTT Topic Rules  |
|   - Parameter Store Business Thresholds               - Simulator X.509 Certificates   |
|  (State: shared-data/ & messaging/terraform.tfstate | Changes: ~Monthly)               |
+---------------------------------------------------------------------------------------+
                                           |
                                  Publishes via SSM
                                           v
+---------------------------------------------------------------------------------------+
|                                  3. MICROSERVICES                                     |
|                                                                                       |
|   +-----------------------+   +-----------------------+   +-----------------------+   |
|   |  telemetry-processor  |   |   processing-engine   |   |     alert-handler     |   |
|   | - Ingests telemetry   |   | - 15s window analysis |   | - Starts countdown    |   |
|   | - Writes Hot Storage  |   | - False positive check|   | - Step Function lease |   |
|   | - Forwards crash flag |   | - Handles LWT dropouts|   | - Cancel / Override   |   |
|   | - Own Task Def & ECR  |   | - Own Task Def & ECR  |   | - Own Task Def & ECR  |   |
|   +-----------------------+   +-----------------------+   +-----------------------+   |
|   (Each service has its own Dockerfile, independent CI/CD, and scoped Terraform stack)|
+---------------------------------------------------------------------------------------+
```

---

## 📁 Repository Directory Structure

```text
.
├── .github/workflows/                      # DECOUPLED CI/CD WORKFLOWS
│   ├── infra-platform.yaml                 # Triggers on changes to infra/platform/**
│   ├── infra-data.yaml                     # Triggers on changes to infra/shared-data/**
│   ├── infra-messaging.yaml                # Triggers on changes to infra/messaging/**
│   ├── infra-monitoring.yaml               # Triggers on changes to infra/monitoring/**
│   ├── infra-services.yaml                 # Triggers on changes to services/**/infra/**
│   ├── svc-telemetry.yaml                  # Triggers on changes to services/telemetry-processor/**
│   ├── svc-processing.yaml                 # Triggers on changes to services/processing-engine/**
│   └── svc-alerts.yaml                     # Triggers on changes to services/alert-handler/**
│
├── infra/                                  # INFRASTRUCTURE AS CODE (TERRAFORM)
│   ├── platform/                           # State: "platform/terraform.tfstate"
│   │   ├── backend.tf
│   │   ├── provider.tf
│   │   ├── vpc.tf                          # VPC, subnets, IGW, S3/DynamoDB endpoints
│   │   ├── security_groups.tf              # ECS security groups
│   │   ├── ecs_cluster.tf                  # Cluster shell, log group, execution role
│   │   ├── oidc.tf                         # GitHub Actions OIDC provider & IAM roles
│   │   └── ssm_outputs.tf                  # Publishes /smart-helmet/platform/*
│   │
│   ├── shared-data/                        # State: "shared-data/terraform.tfstate"
│   │   ├── backend.tf
│   │   ├── provider.tf
│   │   ├── dynamodb.tf                     # Hot storage, Cold storage, Execution registry, Device status
│   │   ├── step_functions.tf               # Emergency countdown & reconciliation workflows
│   │   ├── parameters.tf                   # Business logic threshold parameters
│   │   └── ssm_outputs.tf                  # Publishes /smart-helmet/data/*
│   │
│   ├── messaging/                          # State: "messaging/terraform.tfstate"
│   │   ├── backend.tf
│   │   ├── provider.tf
│   │   ├── queues.tf                       # Telemetry, Control, LWT, Crash, Alert, Override SQS + DLQs
│   │   ├── iot_core.tf                     # IoT rules, simulator certs, SQS forwarding
│   │   └── ssm_outputs.tf                  # Publishes /smart-helmet/queues/*
│   │
│   └── monitoring/                         # State: "monitoring/terraform.tfstate"
│       ├── backend.tf
│       ├── provider.tf
│       ├── data.tf                         # Discovers resources dynamically from SSM
│       └── alarms.tf                       # CloudWatch alarms for DLQs, throttles, errors
│
├── services/                               # MICROSERVICES (Self-contained)
│   ├── telemetry-processor/
│   │   ├── src/ (main.py, requirements.txt)
│   │   ├── Dockerfile
│   │   ├── deploy/task-definition.json     # Declarative ECS task template for CI/CD
│   │   └── infra/                          # State: "services/telemetry-processor/terraform.tfstate"
│   │       ├── data.tf                     # Reads SSM contracts
│   │       ├── ecr.tf                      # ECR repository
│   │       ├── iam.tf                      # Scoped task role
│   │       ├── service.tf                  # ECS service (ignores task_definition drift)
│   │       └── autoscaling.tf              # Queue depth autoscaling
│   │
│   ├── processing-engine/
│   │   ├── src/ (main.py, requirements.txt)
│   │   ├── Dockerfile
│   │   ├── deploy/task-definition.json
│   │   └── infra/                          # State: "services/processing-engine/terraform.tfstate"
│   │       ├── data.tf
│   │       ├── ecr.tf
│   │       ├── iam.tf
│   │       ├── service.tf
│   │       └── autoscaling.tf
│   │
│   └── alert-handler/
│       ├── src/ (main.py, requirements.txt)
│       ├── Dockerfile
│       ├── deploy/task-definition.json
│       └── infra/                          # State: "services/alert-handler/terraform.tfstate"
│           ├── data.tf
│           ├── ecr.tf
│           ├── iam.tf
│           ├── service.tf
│           └── autoscaling.tf
│
├── simulator/                              # IoT Edge Hardware Simulator
│   ├── helmet_sim.py                       # Interactive CLI client for helmet telemetry/crashes
│   ├── load_test.py                        # High-throughput MQTT flood tester
│   └── requirements.txt
│
└── Scripts/
    ├── bootstrapScript.sh                  # One-time S3 state bucket & DynamoDB lock setup
    └── deploy_images.sh                    # Local container build & push helper
```

---

## 🔗 The AWS SSM Parameter Store Contract

Downstream services never hardcode ARNs or reference external Terraform state files directly. The platform and backbone layers publish their outputs into a unified namespace hierarchy:

| SSM Parameter Path | Source Layer | Description |
| :--- | :--- | :--- |
| `/smart-helmet/platform/vpc-id` | `infra/platform` | VPC ID |
| `/smart-helmet/platform/ecs-cluster-name` | `infra/platform` | ECS Fargate Cluster Name |
| `/smart-helmet/platform/ecs-security-group-id` | `infra/platform` | Security Group for Fargate tasks |
| `/smart-helmet/platform/ecs-execution-role-arn` | `infra/platform` | Task Execution Role for pulling ECR images |
| `/smart-helmet/data/hot-storage-name` | `infra/shared-data` | DynamoDB Hot Storage table name |
| `/smart-helmet/data/execution-registry-name` | `infra/shared-data` | DynamoDB Execution Registry table name |
| `/smart-helmet/data/alert-state-machine-arn` | `infra/shared-data` | Step Functions Alert State Machine ARN |
| `/smart-helmet/queues/telemetry-queue-url` | `infra/messaging` | SQS Telemetry Queue URL |
| `/smart-helmet/queues/crash-queue-url` | `infra/messaging` | SQS Crash Queue URL |
| `/smart-helmet/queues/alert-queue-url` | `infra/messaging` | SQS Alert Queue URL |
| `/smart-helmet/config/*` | `infra/shared-data` | Business logic thresholds (windows, TTLs, grace periods) |

---

## 🚀 Deployment & CI/CD Strategy

### 1. Zero Blast-Radius Deployments
- When you push changes to `services/telemetry-processor/src/main.py`, **only `svc-telemetry.yaml` triggers**.
- It builds the new Docker image, tags it with the commit SHA, renders the new task definition, and triggers a rolling ECS update.
- No other databases, queues, or microservices are affected or redeployed.

### 2. Declarative Deployments (No Imperative Bash)
Pipelines utilize AWS's official actions:
- `aws-actions/amazon-ecs-render-task-definition`
- `aws-actions/amazon-ecs-deploy-task-definition`
This eliminates error-prone shell polling scripts and guarantees rollback if new tasks fail health checks.

### 3. Bootstrap Order for Clean Cloud Environments
1. **Bootstrap State Storage**:
   ```bash
   bash Scripts/bootstrapScript.sh
   ```
2. **Provision Foundation Platform**:
   ```bash
   cd infra/platform && terraform init && terraform apply
   ```
3. **Provision Shared Data & Messaging**:
   ```bash
   cd ../shared-data && terraform init && terraform apply
   cd ../messaging && terraform init && terraform apply
   ```
4. **Provision Microservice Infra**:
   ```bash
   cd ../../services/telemetry-processor/infra && terraform init && terraform apply
   cd ../../processing-engine/infra && terraform init && terraform apply
   cd ../../alert-handler/infra && terraform init && terraform apply
   ```
5. **Provision Monitoring**:
   ```bash
   cd ../../../infra/monitoring && terraform init && terraform apply
   ```
