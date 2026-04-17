# AWS Service Mapping — Smart Helmet Infrastructure

This document maps the logical architecture blocks defined in the Data Flow Document to concrete, physical AWS managed services.

## 1. Device Interfacing & Broker Layer

| Logical Component | Physical AWS Service | Reason / Justification |
| :--- | :--- | :--- |
| **MQTT Broker** | **AWS IoT Core** | Fully managed MQTT message broker. Natively handles scaling, Last Will and Testament (LWT) messages, and device authentication. No operational server management needed. |
| **Routing Engine** | **AWS IoT Core Rules Engine** | Evaluates incoming MQTT topics in real-time and routes payloads to ALBs, SQS, or other internal AWS services without custom proxy code. |
| **Device Provisioning/OTA** | **AWS IoT Device Management** | Used by the Fleet Manager for tracking firmware versions, managing fleet state, and executing firmware OTA rollout/rollback jobs. |

## 2. Compute Layer

| Logical Component | Physical AWS Service | Reason / Justification |
| :--- | :--- | :--- |
| **Telemetry Infrastructure** | **Amazon ECS (Fargate)** | Receives massive telemetry batches. Needs fast, stateless HTTP handling. Operates a single ingestion path with internal logic to prioritize 'Live' flags over 'Catch-up' syncs for resource efficiency. |
| **Processing Infrastructure** | **Amazon ECS (Fargate)** | Queue consumer. Reads from Crash, Control, and LWT SQS queues. Validates crash logic using DynamoDB querying. Fits well into a worker-container model. |
| **Alerting Infrastructure** | **Amazon ECS (Fargate)** | Queue consumer for confirmed alerts. Triggers Step Functions workflows. Needs background processing capabilities. |
| **Alert Lifecycle Manager** | **AWS Step Functions** | Handles the 30-second countdown and 5-second false-positive override windows natively. Manages state transitions and wait timers efficiently without consuming long-running container CPU. |

## 3. Asynchronous Messaging Layer

| Logical Component | Physical AWS Service | Reason / Justification |
| :--- | :--- | :--- |
| **Crash Queue** | **Amazon SQS** | Standard queue. Buffers edge-detected crashes prior to cloud processing. Decouples ingestion spikes from Processing Infra capacity. |
| **Control Queue** | **Amazon SQS** | Standard queue. Handles graceful shutdown and low battery events. |
| **LWT Queue** | **Amazon SQS** | Standard queue. Captures unexpected dropouts emitted by IoT Core. |
| **Alert Queue** | **Amazon SQS** | Standard queue. Buffers confirmed crash alerts prior to Delivery (Alerting Infra). |
| **Override Queue** | **Amazon SQS** | Receives cancel and false-positive override signals from the rider. Polled by Alerting Infra to interrupt active State Machine workflows. |
| **Dead Letter Queues (DLQ)** | **Amazon SQS** | For all queues above, catches unprocessable messages/poison pills to prevent queue blocking. |

## 4. Storage Layer

| Logical Component | Physical AWS Service | Reason / Justification |
| :--- | :--- | :--- |
| **Hot Storage** | **Amazon DynamoDB** | Highly performant NoSQL table. Partition key: `Helmet_ID`, Sort key: `Timestamp`. Handles high write velocity natively. TTL feature automates the 24-hour retention requirement. |
| **Cold Storage** | **Amazon DynamoDB** | Separate NoSQL table (On-Demand capacity). Persistent storage for rider info, emergency contacts, event logs, and false positive records. |
| **Execution Registry** | **Amazon DynamoDB** | Key-store mapping `helmet_id` to active Step Function execution ARNs. Enables distributed tasks to cancel the correct alert countdown. |
| **Firmware Storage** | **Amazon S3** | Object storage for storing binary firmware packages pushed during OTA updates. |

## 5. Configuration Layer

| Logical Component | Physical AWS Service | Reason / Justification |
| :--- | :--- | :--- |
| **Application Thresholds**<br>*(e.g., Battery %, Alert Timers)* | **AWS Systems Manager (SSM)<br>Parameter Store** | Centralized config storage. Allows the ECS tasks and Step Functions to fetch thresholds at runtime, enabling updates without code changes or redeployments. |

## 6. Observability Layer

| Logical Component | Physical AWS Service | Reason / Justification |
| :--- | :--- | :--- |
| **Metrics & Dashboards** | **Prometheus + Grafana (on ECS)** | Open-source standard for scraping ECS metrics and application health endpoints. Chosen over pure CloudWatch to demonstrate multi-tool DevOps flexibility. |
| **Alert Routing** | **Prometheus Alertmanager** | Deduplicates and routes operational alerts based on severity. |
| **AWS Native Metrics** | **Amazon CloudWatch** | Monitors IoT Core quotas, DynamoDB RCUs/WCUs, and SQS queue depths. |
| **Telemetry Integration** | **Amazon SNS** | Acts as the glue to forward CloudWatch Alarms to external alerting tools. |
| **Paging & Escalation** | **PagerDuty** (External) | Single pane of glass for all on-call alerting (Engineer & Fleet Manager). |
| **Dead Man's Switch** | **Healthchecks.io** (External) | Pings Prometheus/Alertmanager; if heartbeat stops, pages the engineer independently. |

## 7. Networking & Security Layer

| Logical Component | Physical AWS Service | Reason / Justification |
| :--- | :--- | :--- |
| **Traffic Distribution** | **Application Load Balancer (ALB)** | Routes incoming HTTP telemetry actions from IoT Core rules engine into the Telemetry Infra ECS tasks. |
| **Container Networking** | **Amazon VPC** | Private subnets for ECS tasks and DynamoDB (via VPC endpoints) to ensure data is never exposed to the public internet. |
| **Identity & Access** | **AWS IAM** | Strict roles enforcing least privilege (e.g., Processing Infra can read Hot Storage but cannot publish OTA updates). |

---

*Phase: Implementation Planning / Architecture Design*
*Next Step: Terraform Structure and Repository Layout*
