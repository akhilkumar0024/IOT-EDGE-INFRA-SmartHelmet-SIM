output "infra_alerts_topic_arn" {
  description = "ARN of the infrastructure alerts SNS topic"
  value       = aws_sns_topic.infra_alerts.arn
}
