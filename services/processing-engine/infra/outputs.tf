output "ecr_repository_url" {
  description = "ECR repository URL for processing engine"
  value       = aws_ecr_repository.processing_repo.repository_url
}

output "ecs_service_name" {
  description = "ECS service name for processing engine"
  value       = aws_ecs_service.processing_service.name
}

output "task_definition_arn" {
  description = "ECS task definition ARN for processing engine"
  value       = aws_ecs_task_definition.processing_task.arn
}
