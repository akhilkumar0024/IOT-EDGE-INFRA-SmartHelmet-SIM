# 1. SNS Topic for Infrastructure Alerts
resource "aws_sns_topic" "infra_alerts" {
  name = "smart-helmet-infra-monitoring-alerts-topic"

  tags = {
    Name = "smart-helmet-infra-monitoring-alerts-topic"
  }
}

# 2. SNS Subscription
resource "aws_sns_topic_subscription" "infra_alerts_sub" {
  topic_arn = aws_sns_topic.infra_alerts.arn
  protocol  = "email"
  endpoint  = var.sns-email-address
}

# 3. CloudWatch Alarms for DLQs
locals {
  dlq_map = {
    "telemetry" = data.aws_ssm_parameter.telemetry_dlq_name.value
    "control"   = data.aws_ssm_parameter.control_dlq_name.value
    "lwt"       = data.aws_ssm_parameter.lwt_dlq_name.value
    "crash"     = data.aws_ssm_parameter.crash_dlq_name.value
    "alert"     = data.aws_ssm_parameter.alert_dlq_name.value
    "override"  = data.aws_ssm_parameter.override_dlq_name.value
  }

  queue_names = [
    data.aws_ssm_parameter.telemetry_queue_name.value,
    data.aws_ssm_parameter.control_queue_name.value,
    data.aws_ssm_parameter.lwt_queue_name.value,
    data.aws_ssm_parameter.crash_queue_name.value,
    data.aws_ssm_parameter.alert_queue_name.value,
    data.aws_ssm_parameter.override_queue_name.value
  ]
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

# 4. CloudWatch Alarms for DynamoDB Throttling
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

# 5. IoT Core Throttling Alarm
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

# 6. Step Function Failure Alarm
resource "aws_cloudwatch_metric_alarm" "step_function_failures_alarm" {
  alarm_name          = "smart-helmet-step-function-failures-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 0
  alarm_description   = "Alarm when Step Function executions fail or timeout"
  alarm_actions       = [aws_sns_topic.infra_alerts.arn]

  metric_query {
    id          = "e1"
    expression  = "m1 + m2"
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
}

# 7. SQS Oldest Message Age Alarms
resource "aws_cloudwatch_metric_alarm" "sqs_old_message_alarm" {
  for_each            = toset(local.queue_names)
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
    QueueName = each.key
  }
}

# 8. Application Error Metric Filter & Alarm
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

# 9. ECS Cluster Memory Utilization Alarm
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
