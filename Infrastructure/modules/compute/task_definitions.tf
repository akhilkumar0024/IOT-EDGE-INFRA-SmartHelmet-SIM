#1.Telemetry infra ecs task definition
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
        { name = "TELEMETRY_QUEUE_URL", value = var.telemetry-queue-url },
        { name = "CONTROL_QUEUE_URL", value = var.control-queue-url },
        { name = "CRASH_QUEUE_URL", value = var.crash-queue-url },
        { name = "HOT_STORAGE_NAME", value = var.hot-storage-name }
      ]
    }
  ])
}

#2.Processing infra ecs task definition
resource "aws_ecs_task_definition" "processing-task" {
  family                   = "smart-helmet-processing-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512

  #role that needs to be attached to allow the processing infra instance to access the resources
  task_role_arn = aws_iam_role.Processing-Infra-Role.arn

  #role to allow pulling image from the ECR container
  execution_role_arn = aws_iam_role.ECS-Execution-Role.arn
  container_definitions = jsonencode([
    {
      name      = "processing-container",
      image     = var.processing-code-repo-url,
      essential = true
      environment = [
        { name = "CONTROL_QUEUE_URL", value = var.control-queue-url },
        { name = "CRASH_QUEUE_URL", value = var.crash-queue-url },
        { name = "LWT_QUEUE_URL", value = var.LWT-queue-url },
        { name = "ALERT_QUEUE_URL", value = var.alert-queue-url },
        { name = "HOT_STORAGE_NAME", value = var.hot-storage-name },
        { name = "COLD_STORAGE_NAME", value = var.cold-storage-name }
      ]
    }
  ])
}

#3.Alert infra ecs task definition
resource "aws_ecs_task_definition" "alerts-task" {
  family                   = "smart-helmet-alerts-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512

  #role that needs to be attached to allow the alert infra instance to access the resources
  task_role_arn = aws_iam_role.Alert-Infra-Role.arn

  #role to allow pulling image from the ECR container
  execution_role_arn = aws_iam_role.ECS-Execution-Role.arn
  container_definitions = jsonencode([
    {
      name      = "alerts-container",
      image     = var.alert-code-repo-url,
      essential = true
      environment = [
        { name = "ALERT_QUEUE_URL", value = var.alert-queue-url },
        { name = "OVERRIDE_QUEUE_URL", value = var.override-queue-url },
        { name = "EXECUTION_REGISTRY_NAME", value = var.execution-registry-name }
      ]
    }
  ])
}
