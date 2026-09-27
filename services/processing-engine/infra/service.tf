# ECS Task Definition for Processing Engine
resource "aws_ecs_task_definition" "processing_task" {
  family                   = "smart-helmet-processing-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512

  task_role_arn      = aws_iam_role.processing_role.arn
  execution_role_arn = data.aws_ssm_parameter.ecs_execution_role_arn.value

  container_definitions = jsonencode([
    {
      name      = "processing-container",
      image     = "${aws_ecr_repository.processing_repo.repository_url}:${var.image_tag}",
      essential = true,
      environment = [
        { name = "CONTROL_QUEUE_URL", value = data.aws_ssm_parameter.control_queue_url.value },
        { name = "CRASH_QUEUE_URL", value = data.aws_ssm_parameter.crash_queue_url.value },
        { name = "LWT_QUEUE_URL", value = data.aws_ssm_parameter.lwt_queue_url.value },
        { name = "ALERT_QUEUE_URL", value = data.aws_ssm_parameter.alert_queue_url.value },
        { name = "HOT_STORAGE_NAME", value = data.aws_ssm_parameter.hot_storage_name.value },
        { name = "COLD_STORAGE_NAME", value = data.aws_ssm_parameter.cold_storage_name.value },
        { name = "DEVICE_STATUS_DB_TABLE_NAME", value = data.aws_ssm_parameter.device_status_table_name.value }
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
          "awslogs-stream-prefix" = "processing"
        }
      }
    }
  ])

  tags = {
    Name = "smart-helmet-processing-task"
  }
}

# ECS Fargate Service
resource "aws_ecs_service" "processing_service" {
  name            = "smart-helmet-processing-service"
  cluster         = data.aws_ssm_parameter.ecs_cluster_name.value
  task_definition = aws_ecs_task_definition.processing_task.arn
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
    Name = "smart-helmet-processing-service"
  }
}
