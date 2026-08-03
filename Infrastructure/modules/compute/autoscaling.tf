#1.Autoscaling target for the telemetry infra ecs
resource "aws_appautoscaling_target" "telemetry-infra-target" {
  max_capacity       = 3
  min_capacity       = 1
  resource_id        = "service/${aws_ecs_cluster.smart-helmet-cluster.name}/${aws_ecs_service.smart-helmet-telemetry-service.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

#1.Autoscaling policy for the telemetry infra ecs
resource "aws_appautoscaling_policy" "telemetry_policy" {
  name               = "telemetry-sqs-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.telemetry-infra-target.resource_id
  scalable_dimension = aws_appautoscaling_target.telemetry-infra-target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.telemetry-infra-target.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value = 50.0 # If the queue gets more than 50 messages backed up, scale up!

    # We use a custom metric specification to track the SQS Queue length
    customized_metric_specification {
      metrics {
        label = "Get the telemetry queue depth"
        id    = "m1"
        metric_stat {
          metric {
            namespace   = "AWS/SQS"
            metric_name = "ApproximateNumberOfMessagesVisible"
            dimensions {
              name  = "QueueName"
              value = var.telemetry-queue-name # You might need to add this variable to the compute module
            }
          }
          stat = "Average"
        }
        return_data = true
      }
    }
  }
}


#2. Autoscaling target for the alert infra ecs
resource "aws_appautoscaling_target" "alert-infra-target" {
  max_capacity       = 3
  min_capacity       = 1
  resource_id        = "service/${aws_ecs_cluster.smart-helmet-cluster.name}/${aws_ecs_service.smart-helmet-alerts-service.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# Autoscaling policy for the alert queue
resource "aws_appautoscaling_policy" "alert_queue_policy" {
  name               = "alert-sqs-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.alert-infra-target.resource_id
  scalable_dimension = aws_appautoscaling_target.alert-infra-target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.alert-infra-target.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value = 50.0

    customized_metric_specification {
      metrics {
        label = "Get the alert queue depth"
        id    = "m1"
        metric_stat {
          metric {
            namespace   = "AWS/SQS"
            metric_name = "ApproximateNumberOfMessagesVisible"
            dimensions {
              name  = "QueueName"
              value = var.alert-queue-name
            }
          }
          stat = "Average"
        }
        return_data = true
      }
    }
  }
}

# Autoscaling policy for the override queue
resource "aws_appautoscaling_policy" "override_queue_policy" {
  name               = "override-sqs-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.alert-infra-target.resource_id
  scalable_dimension = aws_appautoscaling_target.alert-infra-target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.alert-infra-target.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value = 50.0

    customized_metric_specification {
      metrics {
        label = "Get the override queue depth"
        id    = "m1"
        metric_stat {
          metric {
            namespace   = "AWS/SQS"
            metric_name = "ApproximateNumberOfMessagesVisible"
            dimensions {
              name  = "QueueName"
              value = var.override-queue-name
            }
          }
          stat = "Average"
        }
        return_data = true
      }
    }
  }
}

#3. Autoscaling target for the processing infra ecs
resource "aws_appautoscaling_target" "processing-infra-target" {
  max_capacity       = 3
  min_capacity       = 1
  resource_id        = "service/${aws_ecs_cluster.smart-helmet-cluster.name}/${aws_ecs_service.smart-helmet-processing-service.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# Autoscaling policy for the crash queue
resource "aws_appautoscaling_policy" "crash_queue_policy" {
  name               = "crash-sqs-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.processing-infra-target.resource_id
  scalable_dimension = aws_appautoscaling_target.processing-infra-target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.processing-infra-target.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value = 50.0

    customized_metric_specification {
      metrics {
        label = "Get the crash queue depth"
        id    = "m1"
        metric_stat {
          metric {
            namespace   = "AWS/SQS"
            metric_name = "ApproximateNumberOfMessagesVisible"
            dimensions {
              name  = "QueueName"
              value = var.crash-queue-name
            }
          }
          stat = "Average"
        }
        return_data = true
      }
    }
  }
}

# Autoscaling policy for the LWT queue
resource "aws_appautoscaling_policy" "lwt_queue_policy" {
  name               = "lwt-sqs-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.processing-infra-target.resource_id
  scalable_dimension = aws_appautoscaling_target.processing-infra-target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.processing-infra-target.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value = 50.0

    customized_metric_specification {
      metrics {
        label = "Get the LWT queue depth"
        id    = "m1"
        metric_stat {
          metric {
            namespace   = "AWS/SQS"
            metric_name = "ApproximateNumberOfMessagesVisible"
            dimensions {
              name  = "QueueName"
              value = var.LWT-queue-name
            }
          }
          stat = "Average"
        }
        return_data = true
      }
    }
  }
}

# Autoscaling policy for the control queue
resource "aws_appautoscaling_policy" "control_queue_policy" {
  name               = "control-sqs-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.processing-infra-target.resource_id
  scalable_dimension = aws_appautoscaling_target.processing-infra-target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.processing-infra-target.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value = 50.0

    customized_metric_specification {
      metrics {
        label = "Get the control queue depth"
        id    = "m1"
        metric_stat {
          metric {
            namespace   = "AWS/SQS"
            metric_name = "ApproximateNumberOfMessagesVisible"
            dimensions {
              name  = "QueueName"
              value = var.control-queue-name
            }
          }
          stat = "Average"
        }
        return_data = true
      }
    }
  }
}
