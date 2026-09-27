# SSM Parameters exported by the Platform Layer for other layers and microservices

resource "aws_ssm_parameter" "vpc_id" {
  name        = "/smart-helmet/platform/vpc-id"
  description = "VPC ID of the Smart Helmet platform"
  type        = "String"
  value       = aws_vpc.main.id
}

resource "aws_ssm_parameter" "public_subnet_ids" {
  name        = "/smart-helmet/platform/public-subnet-ids"
  description = "Comma-separated list of public subnet IDs"
  type        = "StringList"
  value       = join(",", [for s in aws_subnet.public_subnets : s.id])
}

resource "aws_ssm_parameter" "ecs_cluster_name" {
  name        = "/smart-helmet/platform/ecs-cluster-name"
  description = "Name of the ECS Fargate cluster"
  type        = "String"
  value       = aws_ecs_cluster.main.name
}

resource "aws_ssm_parameter" "ecs_cluster_arn" {
  name        = "/smart-helmet/platform/ecs-cluster-arn"
  description = "ARN of the ECS Fargate cluster"
  type        = "String"
  value       = aws_ecs_cluster.main.arn
}

resource "aws_ssm_parameter" "ecs_security_group_id" {
  name        = "/smart-helmet/platform/ecs-security-group-id"
  description = "Security Group ID for ECS microservices"
  type        = "String"
  value       = aws_security_group.ecs_infra_sg.id
}

resource "aws_ssm_parameter" "ecs_execution_role_arn" {
  name        = "/smart-helmet/platform/ecs-execution-role-arn"
  description = "Shared Task Execution Role ARN for pulling images and writing logs"
  type        = "String"
  value       = aws_iam_role.ecs_execution_role.arn
}

resource "aws_ssm_parameter" "ecs_log_group_name" {
  name        = "/smart-helmet/platform/ecs-log-group-name"
  description = "CloudWatch log group name for ECS cluster tasks"
  type        = "String"
  value       = aws_cloudwatch_log_group.ecs_logs.name
}
