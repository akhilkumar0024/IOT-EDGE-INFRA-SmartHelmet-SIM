output "ecr_repository_url" {
  description = "ECR repository URL for alert handler"
  value       = aws_ecr_repository.alert_repo.repository_url
}

output "ecs_service_name" {
  description = "ECS service name for alert handler"
  value       = aws_ecs_service.alerts_service.name
}

output "task_definition_arn" {
  description = "ECS task definition ARN for alert handler"
  value       = aws_ecs_task_definition.alerts_task.arn
}
