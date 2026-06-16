#1. Telemetry Service
resource "aws_ecs_service" "smart-helmet-telemetry-service" {
  name            = "smart-helmet-telemetry-service"
  cluster         = aws_ecs_cluster.smart-helmet-cluster.id
  task_definition = aws_ecs_task_definition.telemetry-task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    #specify the subnet to run the instances in
    subnets = var.public-subnet-ids

    #specify the SG to be attached to the instances
    security_groups  = [var.ecs-security-group-id]
    assign_public_ip = true
  }
}

#2.Processing Service
resource "aws_ecs_service" "smart-helmet-processing-service" {
  name            = "smart-helmet-processing-service"
  cluster         = aws_ecs_cluster.smart-helmet-cluster.id
  task_definition = aws_ecs_task_definition.processing-task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    #specify the subnet to run the instances in
    subnets = var.public-subnet-ids

    #specify the SG to be attached to the instances
    security_groups  = [var.ecs-security-group-id]
    assign_public_ip = true
  }
}

#3.Alert Service
resource "aws_ecs_service" "smart-helmet-alerts-service" {
  name            = "smart-helmet-alerts-service"
  cluster         = aws_ecs_cluster.smart-helmet-cluster.id
  task_definition = aws_ecs_task_definition.alerts-task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    #specify the subnet to run the instances in
    subnets = var.public-subnet-ids

    #specify the SG to be attached to the instances
    security_groups  = [var.ecs-security-group-id]
    assign_public_ip = true
  }
}
