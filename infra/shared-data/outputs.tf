output "hot_storage_name" {
  description = "Name of the hot storage DynamoDB table"
  value       = aws_dynamodb_table.hot_storage.name
}

output "hot_storage_arn" {
  description = "ARN of the hot storage DynamoDB table"
  value       = aws_dynamodb_table.hot_storage.arn
}

output "cold_storage_name" {
  description = "Name of the cold storage DynamoDB table"
  value       = aws_dynamodb_table.cold_storage.name
}

output "cold_storage_arn" {
  description = "ARN of the cold storage DynamoDB table"
  value       = aws_dynamodb_table.cold_storage.arn
}

output "execution_registry_name" {
  description = "Name of the execution registry DynamoDB table"
  value       = aws_dynamodb_table.execution_registry.name
}

output "execution_registry_arn" {
  description = "ARN of the execution registry DynamoDB table"
  value       = aws_dynamodb_table.execution_registry.arn
}

output "device_status_table_name" {
  description = "Name of the device status DynamoDB table"
  value       = aws_dynamodb_table.device_status.name
}

output "device_status_table_arn" {
  description = "ARN of the device status DynamoDB table"
  value       = aws_dynamodb_table.device_status.arn
}

output "alert_state_machine_arn" {
  description = "ARN of the Alert Countdown State Machine"
  value       = aws_sfn_state_machine.alert_state_machine.arn
}

output "reconciliation_state_machine_arn" {
  description = "ARN of the Reconciliation State Machine"
  value       = aws_sfn_state_machine.reconciliation_state_machine.arn
}

output "emergency_alerts_topic_arn" {
  description = "ARN of the emergency alerts SNS topic"
  value       = aws_sns_topic.emergency_alerts.arn
}
