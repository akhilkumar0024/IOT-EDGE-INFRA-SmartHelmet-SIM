# Autoscaling target for Telemetry Service
resource "aws_appautoscaling_target" "telemetry_target" {
  max_capacity       = 3
  min_capacity       = 1
  resource_id        = "service/${data.aws_ssm_parameter.ecs_cluster_name.value}/${aws_ecs_service.telemetry_service.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# Autoscaling policy based on Telemetry Queue Depth
resource "aws_appautoscaling_policy" "telemetry_queue_policy" {
  name               = "telemetry-sqs-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.telemetry_target.resource_id
  scalable_dimension = aws_appautoscaling_target.telemetry_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.telemetry_target.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value = 50.0

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
              value = data.aws_ssm_parameter.telemetry_queue_name.value
            }
          }
          stat = "Average"
        }
        return_data = true
      }
    }
  }
}
