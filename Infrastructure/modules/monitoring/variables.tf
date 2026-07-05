variable "sns-email-address" {
  type        = string
  description = "Email Id To send infra alerts to"
}

variable "telemetry-dlq-name" {
  type        = string
  description = "telemetry dlq name"
}

variable "control-dlq-name" {
  type = string
}

variable "lwt-dlq-name" {
  type = string
}

variable "crash-dlq-name" {
  type = string
}

variable "alert-dlq-name" {
  type = string
}

variable "override-dlq-name" {
  type = string
}

variable "dynamodb-hot-storage-name" {
  type        = string
  description = "DynamoDB Hot Storage name"
}

variable "dynamoDB-cold-storage-name" {
  type        = string
  description = "DynamoDB Cold Storage name"
}

variable "dynamoDB-execution-registry-name" {
  type        = string
  description = "DynamoDB Execution Registry name"
}

variable "step-function-arn" {
  type        = string
  description = "Step Function ARN"
}

variable "queue_names" {
  type        = set(string)
  description = "Set of primary SQS queue names to monitor message age"
}

variable "ecs-log-group-name" {
  type        = string
  description = "CloudWatch Log Group name for ECS Cluster"
}
