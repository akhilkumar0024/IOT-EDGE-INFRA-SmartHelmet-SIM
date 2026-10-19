# ADR-0001: ECS tasks in public subnets with an ingress-free security group, using only free gateway VPC endpoints

- **Status:** Accepted
- **Date:** 2026-10-18
- **Deciders:** Akhil Kumar

## Context

The platform runs three ECS Fargate services (`telemetry-processor`, `processing-engine`,
`alert-handler`). All three are **queue-driven**: they poll SQS, read and write DynamoDB and
SSM Parameter Store, invoke Step Functions, and publish to SES. **No service accepts inbound
network traffic.** Their only HTTP listener is a container health check on `localhost:8080`,
executed from inside the task.

That means the services need **outbound** access only — to ECR (image pulls), SQS, DynamoDB, SSM,
CloudWatch Logs, Step Functions, SES and IoT. There is no requirement for inbound reachability.

Networking options available:

1. **Private subnets + NAT Gateway** — tasks have no public IP; all egress traverses the NAT.
2. **Private subnets + interface VPC endpoints** — egress to AWS services stays on the AWS network.
3. **Public subnets + Internet Gateway** — tasks take a public IP and reach AWS services over the internet.

This deployment is a **single-environment** project that is deliberately torn down and rebuilt
between work sessions. Any resource with a **fixed hourly charge that accrues while idle** is a
direct financial risk, because a forgotten teardown keeps billing indefinitely.

## Decision

Run the ECS tasks in **public subnets with `assign_public_ip = true`**, attached to a shared
security group that has **no ingress rules at all** and a single egress rule allowing all IPv4
traffic outbound.

Use the **free gateway VPC endpoints** for S3 and DynamoDB. Deliberately do **not** create a NAT
Gateway or any interface VPC endpoints.

Inbound exposure is eliminated at the security-group layer rather than the subnet layer: AWS
security groups are deny-by-default, so a security group with zero ingress rules admits no
inbound traffic regardless of the subnet's route table.

## Alternatives rejected

| Option | Why rejected |
|---|---|
| **NAT Gateway** | Fixed hourly charge plus per-GB data processing — a persistent monthly floor that bills 24/7 even when the stack is idle and unused. Directly contrary to the teardown-safety constraint. |
| **Interface VPC Endpoints** | Billed hourly **per AZ, per endpoint**, plus data processing. Reaching every service the tasks need (SQS, SSM, ECR, ECR-dkr, Logs, STS) across two AZs costs substantially more than the NAT Gateway it would replace — for a workload with no inbound requirement. |
| **Private subnets with no egress path** | Not viable — the services must reach ECR, SQS, SSM, Logs and SES. |
| **Gateways endpoints only, private subnets + NAT** | Combines the cost of NAT with no benefit, since there is no inbound traffic to protect. |

## Consequences

**Positive**
- **No fixed networking cost.** Teardown leaves nothing billing — the primary constraint driving this decision.
- **No inbound attack surface.** Zero security-group ingress rules means the tasks are not reachable from the internet, despite holding public IPs.
- **Access control stays with IAM and resource policies** — security groups, task roles, queue policies and DynamoDB conditions — rather than being implicitly delegated to subnet placement.
- Gateway endpoints for S3 and DynamoDB are free, so the highest-volume data paths still avoid internet traversal.

**Negative / accepted**
- **Public IPv4 addresses are not free.** AWS charges approximately **$0.005/hour per in-use public IPv4** — roughly **$22/month at 6 tasks**. This is not zero, and it scales with task count.
- **Egress is unrestricted** (`ip_protocol = "-1"`, `cidr_ipv4 = "0.0.0.0/0"`) rather than scoped to the destinations actually used.
- **No subnet-level defence in depth.** All tasks share one security group and the default network ACL, so subnet boundaries provide no additional isolation between services.

**Residual risk + mitigation**
- *Risk:* if an ingress rule is ever added to this security group, the tasks become directly internet-reachable. *Mitigation:* keep the shared security group ingress-free, and treat any ingress rule as a decision requiring its own ADR.
- *Risk:* a compromised container could exfiltrate to any destination, since egress is unrestricted. *Mitigation:* optional tightening to `tcp/443` + DNS is tracked as a low-priority hardening item.

## Revisit if

- A second environment or any regulated/personal data is introduced, where isolation requirements outweigh fixed cost.
- The deployment becomes long-lived rather than frequently torn down, making a NAT Gateway's fixed cost acceptable.
- Public IPv4 pricing rises relative to NAT Gateway pricing, inverting the comparison.
- Any service acquires a genuine inbound requirement (an ALB, webhooks, a public API).

## References

- `infra/platform/vpc.tf` — VPC, public subnets, internet gateway, S3 and DynamoDB gateway endpoints
- `infra/platform/security_groups.tf` — shared security group (no ingress rules; unrestricted egress)
- `infra/platform/ssm_outputs.tf` — publishes the subnet IDs and security group ID for the service stacks
- `services/*/infra/service.tf` — `network_configuration` with `assign_public_ip = true`

> Cost figures are approximate and were current at the time of writing; verify against the AWS
> pricing page for `ap-south-1` before relying on them.
