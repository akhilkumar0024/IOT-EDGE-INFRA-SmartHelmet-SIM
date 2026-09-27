# SSM Parameters exported by the Shared Data Layer

resource "aws_ssm_parameter" "hot_storage_name" {
  name        = "/smart-helmet/data/hot-storage-name"
  description = "DynamoDB hot storage table name"
  type        = "String"
  value       = aws_dynamodb_table.hot_storage.name
}

resource "aws_ssm_parameter" "hot_storage_arn" {
  name        = "/smart-helmet/data/hot-storage-arn"
  description = "DynamoDB hot storage table ARN"
  type        = "String"
  value       = aws_dynamodb_table.hot_storage.arn
}

resource "aws_ssm_parameter" "cold_storage_name" {
  name        = "/smart-helmet/data/cold-storage-name"
  description = "DynamoDB cold storage table name"
  type        = "String"
  value       = aws_dynamodb_table.cold_storage.name
}

resource "aws_ssm_parameter" "cold_storage_arn" {
  name        = "/smart-helmet/data/cold-storage-arn"
  description = "DynamoDB cold storage table ARN"
  type        = "String"
  value       = aws_dynamodb_table.cold_storage.arn
}

resource "aws_ssm_parameter" "execution_registry_name" {
  name        = "/smart-helmet/data/execution-registry-name"
  description = "DynamoDB execution registry table name"
  type        = "String"
  value       = aws_dynamodb_table.execution_registry.name
}

resource "aws_ssm_parameter" "execution_registry_arn" {
  name        = "/smart-helmet/data/execution-registry-arn"
  description = "DynamoDB execution registry table ARN"
  type        = "String"
  value       = aws_dynamodb_table.execution_registry.arn
}

resource "aws_ssm_parameter" "device_status_table_name" {
  name        = "/smart-helmet/data/device-status-table-name"
  description = "DynamoDB device status table name"
  type        = "String"
  value       = aws_dynamodb_table.device_status.name
}

resource "aws_ssm_parameter" "device_status_table_arn" {
  name        = "/smart-helmet/data/device-status-table-arn"
  description = "DynamoDB device status table ARN"
  type        = "String"
  value       = aws_dynamodb_table.device_status.arn
}

resource "aws_ssm_parameter" "alert_state_machine_arn" {
  name        = "/smart-helmet/data/alert-state-machine-arn"
  description = "ARN of the Alert Countdown State Machine"
  type        = "String"
  value       = aws_sfn_state_machine.alert_state_machine.arn
}

resource "aws_ssm_parameter" "reconciliation_state_machine_arn" {
  name        = "/smart-helmet/data/reconciliation-state-machine-arn"
  description = "ARN of the Reconciliation State Machine"
  type        = "String"
  value       = aws_sfn_state_machine.reconciliation_state_machine.arn
}

resource "aws_ssm_parameter" "emergency_alerts_topic_arn" {
  name        = "/smart-helmet/data/emergency-alerts-topic-arn"
  description = "ARN of the emergency alerts SNS topic"
  type        = "String"
  value       = aws_sns_topic.emergency_alerts.arn
}
