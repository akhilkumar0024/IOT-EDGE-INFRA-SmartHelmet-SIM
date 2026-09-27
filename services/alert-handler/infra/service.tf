# ECS Task Definition for Alert Handler
resource "aws_ecs_task_definition" "alerts_task" {
  family                   = "smart-helmet-alerts-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512

  task_role_arn      = aws_iam_role.alert_role.arn
  execution_role_arn = data.aws_ssm_parameter.ecs_execution_role_arn.value

  container_definitions = jsonencode([
    {
      name      = "alerts-container",
      image     = "${aws_ecr_repository.alert_repo.repository_url}:${var.image_tag}",
      essential = true,
      environment = [
        { name = "ALERT_QUEUE_URL", value = data.aws_ssm_parameter.alert_queue_url.value },
        { name = "OVERRIDE_QUEUE_URL", value = data.aws_ssm_parameter.override_queue_url.value },
        { name = "EXECUTION_REGISTRY_NAME", value = data.aws_ssm_parameter.execution_registry_name.value },
        { name = "STEP_FUNCTION_ARN", value = data.aws_ssm_parameter.alert_state_machine_arn.value },
        { name = "RECONCILIATION_STEP_FUNCTION_ARN", value = data.aws_ssm_parameter.reconciliation_state_machine_arn.value }
      ],
      portMappings = [
        {
          containerPort = 8080,
          protocol      = "tcp"
        }
      ],
      healthCheck = {
        command     = ["CMD-SHELL", "python -c 'import urllib.request; urllib.request.urlopen(\"http://localhost:8080/health\")' || exit 1"],
        interval    = 30,
        timeout     = 5,
        retries     = 3,
        startPeriod = 60
      },
      logConfiguration = {
        logDriver = "awslogs",
        options = {
          "awslogs-group"         = data.aws_ssm_parameter.ecs_log_group_name.value,
          "awslogs-region"        = var.region,
          "awslogs-stream-prefix" = "alerts"
        }
      }
    }
  ])

  tags = {
    Name = "smart-helmet-alerts-task"
  }
}

# ECS Fargate Service
resource "aws_ecs_service" "alerts_service" {
  name            = "smart-helmet-alerts-service"
  cluster         = data.aws_ssm_parameter.ecs_cluster_name.value
  task_definition = aws_ecs_task_definition.alerts_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = split(",", data.aws_ssm_parameter.public_subnet_ids.value)
    security_groups  = [data.aws_ssm_parameter.ecs_security_group_id.value]
    assign_public_ip = true
  }

  lifecycle {
    ignore_changes = [task_definition]
  }

  tags = {
    Name = "smart-helmet-alerts-service"
  }
}
