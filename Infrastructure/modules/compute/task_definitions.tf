resource "aws_ecs_task_definition" "telemetry-task" {
  family                   = "smart-helmet-telemetry-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512

  #role that needs to be attached to allow the telemetry infra instance to access the resources
  task_role_arn = aws_iam_role.Telemetry-Infra-Role.arn

  #role to allow pulling image from the ECR container
  execution_role_arn = aws_iam_role.ECS-Execution-Role.arn
  container_definitions = jsonencode([
    {
      name      = "telemetry-container",
      image     = var.telemetry-code-repo-url,
      essential = true
      environment = [

        { name = "TELEMETRY_QUEUE_URL", value = var.telemetry-queue-arn }
      ]
    }
  ])
}
