resource "aws_sns_topic" "infra_alerts" {
  name = "smart-helmet-infra-monitoring-alerts-topic"

  tags = {
    Name = "smart-helmet-infra-monitoring-alerts-topic"
  }
}

resource "aws_sns_topic_subscription" "infra_alerts_sub" {
  topic_arn = aws_sns_topic.infra_alerts.arn
  protocol  = "email"
  endpoint  = var.sns-email-address
}

locals {
  dlq_map = {
    "telemetry" = data.aws_ssm_parameter.telemetry_dlq_name.value
    "control"   = data.aws_ssm_parameter.control_dlq_name.value
    "lwt"       = data.aws_ssm_parameter.lwt_dlq_name.value
    "crash"     = data.aws_ssm_parameter.crash_dlq_name.value
    "alert"     = data.aws_ssm_parameter.alert_dlq_name.value
    "override"  = data.aws_ssm_parameter.override_dlq_name.value
  }

  queue_map = {
    "telemetry" = data.aws_ssm_parameter.telemetry_queue_name.value
    "control"   = data.aws_ssm_parameter.control_queue_name.value
    "lwt"       = data.aws_ssm_parameter.lwt_queue_name.value
    "crash"     = data.aws_ssm_parameter.crash_queue_name.value
    "alert"     = data.aws_ssm_parameter.alert_queue_name.value
    "override"  = data.aws_ssm_parameter.override_queue_name.value
  }
}

resource "aws_cloudwatch_metric_alarm" "dlq_alarms" {
  for_each            = local.dlq_map
  alarm_name          = "smart-helmet-${each.key}-dlq-alarm"
  alarm_description   = "Alarm when ${each.key} DLQ has messages"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  evaluation_periods  = 1
  period              = 60
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  statistic           = "Sum"

  dimensions = {
    QueueName = each.value
  }

  alarm_actions = [aws_sns_topic.infra_alerts.arn]
}

locals {
  dynamodb_tables = {
    "hot-storage"        = data.aws_ssm_parameter.hot_storage_name.value
    "cold-storage"       = data.aws_ssm_parameter.cold_storage_name.value
    "execution-registry" = data.aws_ssm_parameter.execution_registry_name.value
  }
}

resource "aws_cloudwatch_metric_alarm" "dynamodb_throttle_alarms" {
  for_each            = local.dynamodb_tables
  alarm_name          = "smart-helmet-dynamodb-${each.key}-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 0
  alarm_description   = "Alarm when DynamoDB ${each.key} experiences Read or Write throttling"
  alarm_actions       = [aws_sns_topic.infra_alerts.arn]

  metric_query {
    id          = "e1"
    expression  = "m1 + m2"
    label       = "DynamoDBTotalThrottleEvents"
    return_data = true
  }

  metric_query {
    id = "m1"
    metric {
      metric_name = "ReadThrottleEvents"
      namespace   = "AWS/DynamoDB"
      period      = 60
      stat        = "Sum"
      dimensions = {
        TableName = each.value
      }
    }
  }

  metric_query {
    id = "m2"
    metric {
      metric_name = "WriteThrottleEvents"
      namespace   = "AWS/DynamoDB"
      period      = 60
      stat        = "Sum"
      dimensions = {
        TableName = each.value
      }
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "iot_core_throttling_alarm" {
  alarm_name          = "smart-helmet-iot-core-throttling-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "RuleMessageThrottled"
  namespace           = "AWS/IoT"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Alarm when IoT Core drops messages due to rate limits"
  alarm_actions       = [aws_sns_topic.infra_alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "step_function_failures_alarm" {
  alarm_name          = "smart-helmet-step-function-failures-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 0
  alarm_description   = "Alarm when Step Function executions fail or timeout"
  alarm_actions       = [aws_sns_topic.infra_alerts.arn]

  metric_query {
    id          = "e1"
    expression  = "m1 + m2 + m3 + m4"
    label       = "TotalFailuresAndTimeouts"
    return_data = true
  }

  metric_query {
    id = "m1"
    metric {
      metric_name = "ExecutionsFailed"
      namespace   = "AWS/States"
      period      = 60
      stat        = "Sum"
      dimensions = {
        StateMachineArn = data.aws_ssm_parameter.alert_state_machine_arn.value
      }
    }
  }

  metric_query {
    id = "m2"
    metric {
      metric_name = "ExecutionsTimedOut"
      namespace   = "AWS/States"
      period      = 60
      stat        = "Sum"
      dimensions = {
        StateMachineArn = data.aws_ssm_parameter.alert_state_machine_arn.value
      }
    }
  }

  # Reconciliation workflow failures were previously invisible to this alarm.
  metric_query {
    id = "m3"
    metric {
      metric_name = "ExecutionsFailed"
      namespace   = "AWS/States"
      period      = 60
      stat        = "Sum"
      dimensions = {
        StateMachineArn = data.aws_ssm_parameter.reconciliation_state_machine_arn.value
      }
    }
  }

  metric_query {
    id = "m4"
    metric {
      metric_name = "ExecutionsTimedOut"
      namespace   = "AWS/States"
      period      = 60
      stat        = "Sum"
      dimensions = {
        StateMachineArn = data.aws_ssm_parameter.reconciliation_state_machine_arn.value
      }
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "sqs_old_message_alarm" {
  for_each            = local.queue_map
  alarm_name          = "smart-helmet-sqs-${each.key}-old-message-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateAgeOfOldestMessage"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Maximum"
  threshold           = 600
  alarm_description   = "Alarm if a message sits in the queue for more than 10 minutes"
  alarm_actions       = [aws_sns_topic.infra_alerts.arn]

  dimensions = {
    QueueName = each.value
  }
}

resource "aws_cloudwatch_log_metric_filter" "ecs_error_filter" {
  name           = "smart-helmet-ecs-error-filter"
  pattern        = "ERROR"
  log_group_name = data.aws_ssm_parameter.ecs_log_group_name.value

  metric_transformation {
    name      = "ApplicationErrorCount"
    namespace = "SmartHelmet/ApplicationLogs"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "ecs_error_alarm" {
  alarm_name          = "smart-helmet-ecs-error-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = aws_cloudwatch_log_metric_filter.ecs_error_filter.metric_transformation[0].name
  namespace           = aws_cloudwatch_log_metric_filter.ecs_error_filter.metric_transformation[0].namespace
  period              = 60
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "Alarm when application logs 'ERROR' more than 5 times in a minute"
  alarm_actions       = [aws_sns_topic.infra_alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "ecs_memory_alarm" {
  alarm_name          = "smart-helmet-ecs-memory-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 90
  alarm_description   = "Alarm when ECS Cluster Memory goes above 90% (OOM risk)"
  alarm_actions       = [aws_sns_topic.infra_alerts.arn]

  dimensions = {
    ClusterName = data.aws_ssm_parameter.ecs_cluster_name.value
  }
}

# The cluster-level alarm above averages across all three services, so one
# service running hot is invisible in it, and nothing at all fires when a
# service is simply not running.
locals {
  ecs_services = {
    "telemetry"  = "smart-helmet-telemetry-service"
    "processing" = "smart-helmet-processing-service"
    "alerts"     = "smart-helmet-alerts-service"
  }
}

resource "aws_cloudwatch_metric_alarm" "ecs_tasks_below_desired" {
  for_each            = local.ecs_services
  alarm_name          = "smart-helmet-${each.key}-tasks-below-desired"
  alarm_description   = "Alarm when ${each.key} runs fewer tasks than its desired count"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  alarm_actions       = [aws_sns_topic.infra_alerts.arn]

  # Three consecutive minutes: a scale-out raises DesiredTaskCount before the
  # new tasks reach RUNNING, so a single-period alarm would fire on every
  # routine scale-out. A real outage stays below desired indefinitely.
  evaluation_periods  = 3
  datapoints_to_alarm = 3

  metric_query {
    id          = "e1"
    expression  = "desired - running"
    label       = "TasksBelowDesired"
    return_data = true
  }

  metric_query {
    id = "running"
    metric {
      metric_name = "RunningTaskCount"
      namespace   = "ECS/ContainerInsights"
      period      = 60
      stat        = "Average"
      dimensions = {
        ClusterName = data.aws_ssm_parameter.ecs_cluster_name.value
        ServiceName = each.value
      }
    }
  }

  metric_query {
    id = "desired"
    metric {
      metric_name = "DesiredTaskCount"
      namespace   = "ECS/ContainerInsights"
      period      = 60
      stat        = "Average"
      dimensions = {
        ClusterName = data.aws_ssm_parameter.ecs_cluster_name.value
        ServiceName = each.value
      }
    }
  }
}

# Autoscaling targets SQS depth, not CPU, so a saturated service that cannot
# scale further has no other signal.
resource "aws_cloudwatch_metric_alarm" "ecs_cpu_saturation" {
  for_each            = local.ecs_services
  alarm_name          = "smart-helmet-${each.key}-cpu-saturation"
  alarm_description   = "Alarm when ${each.key} averages over 80% CPU for 5 minutes"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 5
  datapoints_to_alarm = 5
  threshold           = 80
  namespace           = "AWS/ECS"
  metric_name         = "CPUUtilization"
  period              = 60
  statistic           = "Average"
  alarm_actions       = [aws_sns_topic.infra_alerts.arn]

  dimensions = {
    ClusterName = data.aws_ssm_parameter.ecs_cluster_name.value
    ServiceName = each.value
  }
}

resource "aws_cloudwatch_metric_alarm" "ecs_service_memory_alarm" {
  for_each            = local.ecs_services
  alarm_name          = "smart-helmet-${each.key}-memory-saturation"
  alarm_description   = "Alarm when ${each.key} averages over 90% memory for 5 minutes"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 5
  datapoints_to_alarm = 5
  threshold           = 90
  namespace           = "AWS/ECS"
  metric_name         = "MemoryUtilization"
  period              = 60
  statistic           = "Average"
  alarm_actions       = [aws_sns_topic.infra_alerts.arn]

  dimensions = {
    ClusterName = data.aws_ssm_parameter.ecs_cluster_name.value
    ServiceName = each.value
  }
}
