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
        { name = "COLD_STORAGE_NAME", value = data.aws_ssm_parameter.cold_storage_name.value },
        { name = "STEP_FUNCTION_ARN", value = data.aws_ssm_parameter.alert_state_machine_arn.value },
        { name = "RECONCILIATION_STEP_FUNCTION_ARN", value = data.aws_ssm_parameter.reconciliation_state_machine_arn.value },
        { name = "AWS_REGION", value = var.region }
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

resource "aws_ecs_service" "alerts_service" {
  name            = "smart-helmet-alerts-service"
  cluster         = data.aws_ssm_parameter.ecs_cluster_name.value
  task_definition = aws_ecs_task_definition.alerts_task.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  # Roll back automatically if the new tasks never become healthy, rather than
  # leaving the service stuck on a failed deployment until a human intervenes.
  # The task definition carries a container health check, so this detects
  # "started but unhealthy", not just "failed to launch".
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  # Keep the current tasks healthy while the new ones prove themselves, and
  # allow up to double the task count during a rollout.
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  network_configuration {
    subnets          = split(",", data.aws_ssm_parameter.public_subnet_ids.value)
    security_groups  = [data.aws_ssm_parameter.ecs_security_group_id.value]
    assign_public_ip = true
  }

  lifecycle {
    # task_definition is owned by the CI deploy workflow (it registers new
    # revisions). desired_count is owned by Application Auto Scaling at
    # runtime - without this, every apply would reset a scaled-out service
    # back to the configured seed and undo the scale-out.
    ignore_changes = [task_definition, desired_count]
  }

  tags = {
    Name = "smart-helmet-alerts-service"
  }
}
