output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = [for s in aws_subnet.public_subnets : s.id]
}

output "ecs_cluster_name" {
  description = "The name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

output "ecs_cluster_arn" {
  description = "The ARN of the ECS cluster"
  value       = aws_ecs_cluster.main.arn
}

output "ecs_security_group_id" {
  description = "The ID of the ECS Security Group"
  value       = aws_security_group.ecs_infra_sg.id
}

output "ecs_execution_role_arn" {
  description = "The ARN of the shared ECS Execution Role"
  value       = aws_iam_role.ecs_execution_role.arn
}

output "ecs_log_group_name" {
  description = "The CloudWatch Log Group for ECS"
  value       = aws_cloudwatch_log_group.ecs_logs.name
}
