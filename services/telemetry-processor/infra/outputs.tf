output "ecr_repository_url" {
  description = "ECR repository URL for telemetry processor"
  value       = aws_ecr_repository.telemetry_repo.repository_url
}

output "ecs_service_name" {
  description = "ECS service name for telemetry processor"
  value       = aws_ecs_service.telemetry_service.name
}

output "task_definition_arn" {
  description = "ECS task definition ARN for telemetry processor"
  value       = aws_ecs_task_definition.telemetry_task.arn
}
