resource "aws_ecs_cluster" "smart-helmet-cluster" {
  name = "smart-helmet-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

#2. CloudWatch Log Group for ECS
resource "aws_cloudwatch_log_group" "ecs_log_group" {
  name              = "/ecs/smart-helmet-cluster"
  retention_in_days = 14
}
