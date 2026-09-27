# Autoscaling Target for Alert Handler
resource "aws_appautoscaling_target" "alerts_target" {
  max_capacity       = 3
  min_capacity       = 1
  resource_id        = "service/${data.aws_ssm_parameter.ecs_cluster_name.value}/${aws_ecs_service.alerts_service.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# Autoscaling policy for Alert Queue
resource "aws_appautoscaling_policy" "alert_queue_policy" {
  name               = "alert-sqs-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.alerts_target.resource_id
  scalable_dimension = aws_appautoscaling_target.alerts_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.alerts_target.service_namespace

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
              value = data.aws_ssm_parameter.alert_queue_name.value
            }
          }
          stat = "Average"
        }
        return_data = true
      }
    }
  }
}

# Autoscaling policy for Override Queue
resource "aws_appautoscaling_policy" "override_queue_policy" {
  name               = "override-sqs-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.alerts_target.resource_id
  scalable_dimension = aws_appautoscaling_target.alerts_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.alerts_target.service_namespace

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
              value = data.aws_ssm_parameter.override_queue_name.value
            }
          }
          stat = "Average"
        }
        return_data = true
      }
    }
  }
}
