# 1. ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = var.ecs-cluster-name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = var.ecs-cluster-name
  }
}

# 2. CloudWatch Log Group for ECS Services
resource "aws_cloudwatch_log_group" "ecs_logs" {
  name              = var.ecs-log-group-name
  retention_in_days = 30

  tags = {
    Name = var.ecs-log-group-name
  }
}

# 3. ECS Task Execution Role (Shared by all services to pull images and write logs)
resource "aws_iam_role" "ecs_execution_role" {
  name = "smart-helmet-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "smart-helmet-ecs-execution-role"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_execution_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
