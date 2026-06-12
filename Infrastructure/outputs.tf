output "vpc-id" {
  description = "The ID of the VPC"
  value       = module.networking.vpc-id
}

output "public-subnet-id" {
  description = "List of IDs of the public subnets"
  value       = module.networking.public-subnet-ids
}

output "public-subnet-name" {
  description = "List of names of the public subnets"
  value       = module.networking.public-subnet-names
}

output "aws-sg-ecs-infra-information" {
  description = "Information about the ECS Security Group"
  value = {
    id   = module.ecs-security-group.aws-sg-ecs-infra-id
    name = module.ecs-security-group.aws-sg-ecs-infra-name
  }
}

output "hot-storage-information" {
  description = "info on hot storage DB"
  value = {
    name = module.database.hot-storage-name
    arn  = module.database.hot-storage-arn
    id   = module.database.hot-storage-id
  }
}

output "cold-storage-information" {
  description = "info on cold storage DB"
  value = {
    name = module.database.cold-storage-name
    arn  = module.database.cold-storage-arn
    id   = module.database.cold-storage-id
  }
}

output "execution-registry-information" {
  description = "info on execution registry DB"
  value = {
    name = module.database.execution-registry-name
    arn  = module.database.execution-registry-arn
    id   = module.database.execution-registry-id
  }
}

output "telemetry-queue-information" {
  description = "info on telemetry queue"
  value = {
    queue_url = module.messaging.telemetry-queue-url
    queue_arn = module.messaging.telemetry-queue-arn
    dlq_url   = module.messaging.telemetry-dlq-url
    dlq_arn   = module.messaging.telemetry-dlq-arn
  }
}

output "control-queue-information" {
  description = "info on control queue"
  value = {
    queue_url = module.messaging.control-queue-url
    queue_arn = module.messaging.control-queue-arn
    dlq_url   = module.messaging.control-dlq-url
    dlq_arn   = module.messaging.control-dlq-arn
  }
}

output "lwt-queue-information" {
  description = "info on LWT queue"
  value = {
    queue_url = module.messaging.lwt-queue-url
    queue_arn = module.messaging.lwt-queue-arn
    dlq_url   = module.messaging.lwt-dlq-url
    dlq_arn   = module.messaging.lwt-dlq-arn
  }
}

output "crash-queue-information" {
  description = "info on crash queue"
  value = {
    queue_url = module.messaging.crash-queue-url
    queue_arn = module.messaging.crash-queue-arn
    dlq_url   = module.messaging.crash-dlq-url
    dlq_arn   = module.messaging.crash-dlq-arn
  }
}

output "alert-queue-information" {
  description = "info on alert queue"
  value = {
    queue_url = module.messaging.alert-queue-url
    queue_arn = module.messaging.alert-queue-arn
    dlq_url   = module.messaging.alert-dlq-url
    dlq_arn   = module.messaging.alert-dlq-arn
  }
}

output "override-queue-information" {
  description = "info on override queue"
  value = {
    queue_url = module.messaging.override-queue-url
    queue_arn = module.messaging.override-queue-arn
    dlq_url   = module.messaging.override-dlq-url
    dlq_arn   = module.messaging.override-dlq-arn
  }
}

output "compute-iam-roles" {
  description = "IAM Role ARNs for the compute infrastructure"
  value = {
    telemetry_role_arn  = module.compute.telemetry-infra-role-arn
    processing_role_arn = module.compute.processing-infra-role-arn
    alert_role_arn      = module.compute.alert-infra-role-arn
  }
}
