resource "aws_ecs_cluster" "smart-helmet-cluster" {
  name = "smart-helmet-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

