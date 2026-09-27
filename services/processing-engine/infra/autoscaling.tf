# Autoscaling Target for Processing Engine
resource "aws_appautoscaling_target" "processing_target" {
  max_capacity       = 3
  min_capacity       = 1
  resource_id        = "service/${data.aws_ssm_parameter.ecs_cluster_name.value}/${aws_ecs_service.processing_service.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# Autoscaling policy for Crash Queue Depth
resource "aws_appautoscaling_policy" "crash_queue_policy" {
  name               = "crash-sqs-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.processing_target.resource_id
  scalable_dimension = aws_appautoscaling_target.processing_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.processing_target.service_namespace

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
              value = data.aws_ssm_parameter.crash_queue_name.value
            }
          }
          stat = "Average"
        }
        return_data = true
      }
    }
  }
}

# Autoscaling policy for LWT Queue Depth
resource "aws_appautoscaling_policy" "lwt_queue_policy" {
  name               = "lwt-sqs-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.processing_target.resource_id
  scalable_dimension = aws_appautoscaling_target.processing_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.processing_target.service_namespace

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
              value = data.aws_ssm_parameter.lwt_queue_name.value
            }
          }
          stat = "Average"
        }
        return_data = true
      }
    }
  }
}

# Autoscaling policy for Control Queue Depth
resource "aws_appautoscaling_policy" "control_queue_policy" {
  name               = "control-sqs-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.processing_target.resource_id
  scalable_dimension = aws_appautoscaling_target.processing_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.processing_target.service_namespace

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
              value = data.aws_ssm_parameter.control_queue_name.value
            }
          }
          stat = "Average"
        }
        return_data = true
      }
    }
  }
}
