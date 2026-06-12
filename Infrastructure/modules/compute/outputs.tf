output "telemetry-infra-role-arn" {
  description = "ARN of the Telemetry Infra IAM Role"
  value       = aws_iam_role.Telemetry-Infra-Role.arn
}

output "processing-infra-role-arn" {
  description = "ARN of the Processing Infra IAM Role"
  value       = aws_iam_role.Processing-Infra-Role.arn
}

output "alert-infra-role-arn" {
  description = "ARN of the Alert Infra IAM Role"
  value       = aws_iam_role.Alert-Infra-Role.arn
}
