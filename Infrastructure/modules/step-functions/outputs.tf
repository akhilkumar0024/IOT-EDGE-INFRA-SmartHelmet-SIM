output "state_machine_arn" {
  description = "The ARN of the Alert Infra State Machine"
  value       = aws_sfn_state_machine.alert_state_machine.arn
}

output "reconciliation_state_machine_arn" {
  description = "The ARN of the Reconciliation State Machine"
  value       = aws_sfn_state_machine.reconciliation_state_machine.arn
}
