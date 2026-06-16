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
