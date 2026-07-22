variable "telemetry-queue-arn" {
  type = string
}

variable "control-queue-arn" {
  type = string
}

variable "crash-queue-arn" {
  type = string
}

variable "alert-queue-arn" {
  type = string
}

variable "LWT-queue-arn" {
  type = string
}

variable "override-queue-arn" {
  type = string
}

variable "hot-storage-arn" {
  type = string
}

variable "cold-storage-arn" {
  type = string
}

variable "execution-registry-arn" {
  type = string
}


variable "telemetry-code-repo-url" {
  description = "the ECR URL for the telemetry infra image"
  type        = string
}

variable "processing-code-repo-url" {
  description = "the ECR URL for the processing infra image"
  type        = string
}

variable "alert-code-repo-url" {
  description = "the ECR URL for the alert infra image"
  type        = string
}

variable "public-subnet-ids" {
  description = "ids of the public subnets"
  type        = list(string)
}

variable "ecs-security-group-id" {
  description = "id of the SG"
  type        = string
}

variable "telemetry-queue-url" { type = string }
variable "control-queue-url" { type = string }
variable "crash-queue-url" { type = string }
variable "alert-queue-url" { type = string }
variable "LWT-queue-url" { type = string }
variable "override-queue-url" { type = string }
variable "hot-storage-name" { type = string }
variable "cold-storage-name" { type = string }
variable "execution-registry-name" { type = string }

variable "step_function_arn" {
  description = "The ARN of the Alert Step Function"
  type        = string
}

variable "reconciliation_step_function_arn" {
  description = "The ARN of the Reconciliation Step Function"
  type        = string
}

variable "telemetry-queue-name" {
  description = "name of the telemetry queue"
  type        = string
}

variable "alert-queue-name" {
  description = "name of the alert queue"
  type        = string
}

variable "override-queue-name" {
  description = "name of the override queue"
  type        = string
}

variable "LWT-queue-name" {
  description = "name of the LWT queue"
  type        = string
}

variable "control-queue-name" {
  description = "name of the control queue"
  type        = string
}

variable "crash-queue-name" {
  description = "name of the crash queue"
  type        = string
}

variable "ecs-log-group-name" {
  description = "CloudWatch Log Group name for ECS Cluster"
  type        = string
}

variable "device-status-db-table-name" {
  type        = string
  description = "Name of the device status DynamoDB table"
}

variable "device-status-db-table-arn" {
  type        = string
  description = "ARN of the device status DynamoDB table"
}
