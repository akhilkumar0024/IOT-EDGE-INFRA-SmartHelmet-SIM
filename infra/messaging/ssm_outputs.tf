# SSM Parameters exported by the Messaging Layer for microservices

# Queue URLs
resource "aws_ssm_parameter" "telemetry_queue_url" {
  name        = "/smart-helmet/queues/telemetry-queue-url"
  description = "Telemetry SQS queue URL"
  type        = "String"
  value       = aws_sqs_queue.telemetry_queue.url
}

resource "aws_ssm_parameter" "control_queue_url" {
  name        = "/smart-helmet/queues/control-queue-url"
  description = "Control SQS queue URL"
  type        = "String"
  value       = aws_sqs_queue.control_queue.url
}

resource "aws_ssm_parameter" "lwt_queue_url" {
  name        = "/smart-helmet/queues/lwt-queue-url"
  description = "LWT SQS queue URL"
  type        = "String"
  value       = aws_sqs_queue.lwt_queue.url
}

resource "aws_ssm_parameter" "crash_queue_url" {
  name        = "/smart-helmet/queues/crash-queue-url"
  description = "Crash SQS queue URL"
  type        = "String"
  value       = aws_sqs_queue.crash_queue.url
}

resource "aws_ssm_parameter" "alert_queue_url" {
  name        = "/smart-helmet/queues/alert-queue-url"
  description = "Alert SQS queue URL"
  type        = "String"
  value       = aws_sqs_queue.alert_queue.url
}

resource "aws_ssm_parameter" "override_queue_url" {
  name        = "/smart-helmet/queues/override-queue-url"
  description = "Override SQS queue URL"
  type        = "String"
  value       = aws_sqs_queue.override_queue.url
}

# Queue ARNs
resource "aws_ssm_parameter" "telemetry_queue_arn" {
  name        = "/smart-helmet/queues/telemetry-queue-arn"
  description = "Telemetry SQS queue ARN"
  type        = "String"
  value       = aws_sqs_queue.telemetry_queue.arn
}

resource "aws_ssm_parameter" "control_queue_arn" {
  name        = "/smart-helmet/queues/control-queue-arn"
  description = "Control SQS queue ARN"
  type        = "String"
  value       = aws_sqs_queue.control_queue.arn
}

resource "aws_ssm_parameter" "lwt_queue_arn" {
  name        = "/smart-helmet/queues/lwt-queue-arn"
  description = "LWT SQS queue ARN"
  type        = "String"
  value       = aws_sqs_queue.lwt_queue.arn
}

resource "aws_ssm_parameter" "crash_queue_arn" {
  name        = "/smart-helmet/queues/crash-queue-arn"
  description = "Crash SQS queue ARN"
  type        = "String"
  value       = aws_sqs_queue.crash_queue.arn
}

resource "aws_ssm_parameter" "alert_queue_arn" {
  name        = "/smart-helmet/queues/alert-queue-arn"
  description = "Alert SQS queue ARN"
  type        = "String"
  value       = aws_sqs_queue.alert_queue.arn
}

resource "aws_ssm_parameter" "override_queue_arn" {
  name        = "/smart-helmet/queues/override-queue-arn"
  description = "Override SQS queue ARN"
  type        = "String"
  value       = aws_sqs_queue.override_queue.arn
}

# Queue Names (for CloudWatch alarms and autoscaling)
resource "aws_ssm_parameter" "telemetry_queue_name" {
  name        = "/smart-helmet/queues/telemetry-queue-name"
  description = "Telemetry SQS queue name"
  type        = "String"
  value       = aws_sqs_queue.telemetry_queue.name
}

resource "aws_ssm_parameter" "control_queue_name" {
  name        = "/smart-helmet/queues/control-queue-name"
  description = "Control SQS queue name"
  type        = "String"
  value       = aws_sqs_queue.control_queue.name
}

resource "aws_ssm_parameter" "lwt_queue_name" {
  name        = "/smart-helmet/queues/lwt-queue-name"
  description = "LWT SQS queue name"
  type        = "String"
  value       = aws_sqs_queue.lwt_queue.name
}

resource "aws_ssm_parameter" "crash_queue_name" {
  name        = "/smart-helmet/queues/crash-queue-name"
  description = "Crash SQS queue name"
  type        = "String"
  value       = aws_sqs_queue.crash_queue.name
}

resource "aws_ssm_parameter" "alert_queue_name" {
  name        = "/smart-helmet/queues/alert-queue-name"
  description = "Alert SQS queue name"
  type        = "String"
  value       = aws_sqs_queue.alert_queue.name
}

resource "aws_ssm_parameter" "override_queue_name" {
  name        = "/smart-helmet/queues/override-queue-name"
  description = "Override SQS queue name"
  type        = "String"
  value       = aws_sqs_queue.override_queue.name
}

# DLQ Names
resource "aws_ssm_parameter" "telemetry_dlq_name" {
  name        = "/smart-helmet/queues/telemetry-dlq-name"
  description = "Telemetry DLQ name"
  type        = "String"
  value       = aws_sqs_queue.telemetry_dlq.name
}

resource "aws_ssm_parameter" "control_dlq_name" {
  name        = "/smart-helmet/queues/control-dlq-name"
  description = "Control DLQ name"
  type        = "String"
  value       = aws_sqs_queue.control_dlq.name
}

resource "aws_ssm_parameter" "lwt_dlq_name" {
  name        = "/smart-helmet/queues/lwt-dlq-name"
  description = "LWT DLQ name"
  type        = "String"
  value       = aws_sqs_queue.lwt_dlq.name
}

resource "aws_ssm_parameter" "crash_dlq_name" {
  name        = "/smart-helmet/queues/crash-dlq-name"
  description = "Crash DLQ name"
  type        = "String"
  value       = aws_sqs_queue.crash_dlq.name
}

resource "aws_ssm_parameter" "alert_dlq_name" {
  name        = "/smart-helmet/queues/alert-dlq-name"
  description = "Alert DLQ name"
  type        = "String"
  value       = aws_sqs_queue.alert_dlq.name
}

resource "aws_ssm_parameter" "override_dlq_name" {
  name        = "/smart-helmet/queues/override-dlq-name"
  description = "Override DLQ name"
  type        = "String"
  value       = aws_sqs_queue.override_dlq.name
}
