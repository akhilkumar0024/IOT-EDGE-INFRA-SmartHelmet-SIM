# 1. SNS Topic
resource "aws_sns_topic" "smart-helmet-infra-alerts" {
  name = "smart-helmet-infra-monitoring-alerts-topic"
}

# 2. SNS Subscription
resource "aws_sns_topic_subscription" "smart-helmet-infra-alerts" {
  topic_arn = aws_sns_topic.smart-helmet-infra-alerts.arn
  protocol  = "email"
  endpoint  = var.sns-email-address
}

# 1. Cloudwatch Alarm For Telemetry DLQ
resource "aws_cloudwatch_metric_alarm" "telemetry_dlq_alarm" {
  alarm_name        = "smart-helmet-telemetry-dlq-alarm"
  alarm_description = "Alarm when Telemetry DLQ has messages"

  comparison_operator = "GreaterThanThreshold"
  threshold           = "0"
  evaluation_periods  = "1"
  period             = "60"

  namespace   = "AWS/SQS"
  metric_name = "ApproximateNumberOfMessagesVisible"
  statistic   = "Sum"

  dimensions = {
    QueueName = var.telemetry-dlq-name
  }

  alarm_actions = [aws_sns_topic.smart-helmet-infra-alerts.arn]
}

# 2. Cloudwatch Alarm For Control DLQ
resource "aws_cloudwatch_metric_alarm" "control_dlq_alarm" {
  alarm_name          = "smart-helmet-control-dlq-alarm"
  alarm_description   = "Alarm when Control DLQ has messages"
  comparison_operator = "GreaterThanThreshold"
  threshold           = "0"
  evaluation_periods  = "1"
  period              = "60"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  statistic           = "Sum"
  dimensions = {
    QueueName = var.control-dlq-name
  }
  alarm_actions = [aws_sns_topic.smart-helmet-infra-alerts.arn]
}

# 3. Cloudwatch Alarm For LWT DLQ
resource "aws_cloudwatch_metric_alarm" "lwt_dlq_alarm" {
  alarm_name          = "smart-helmet-lwt-dlq-alarm"
  alarm_description   = "Alarm when LWT DLQ has messages"
  comparison_operator = "GreaterThanThreshold"
  threshold           = "0"
  evaluation_periods  = "1"
  period              = "60"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  statistic           = "Sum"
  dimensions = {
    QueueName = var.lwt-dlq-name
  }
  alarm_actions = [aws_sns_topic.smart-helmet-infra-alerts.arn]
}

# 4. Cloudwatch Alarm For Crash DLQ
resource "aws_cloudwatch_metric_alarm" "crash_dlq_alarm" {
  alarm_name          = "smart-helmet-crash-dlq-alarm"
  alarm_description   = "Alarm when Crash DLQ has messages"
  comparison_operator = "GreaterThanThreshold"
  threshold           = "0"
  evaluation_periods  = "1"
  period              = "60"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  statistic           = "Sum"
  dimensions = {
    QueueName = var.crash-dlq-name
  }
  alarm_actions = [aws_sns_topic.smart-helmet-infra-alerts.arn]
}

# 5. Cloudwatch Alarm For Alert DLQ
resource "aws_cloudwatch_metric_alarm" "alert_dlq_alarm" {
  alarm_name          = "smart-helmet-alert-dlq-alarm"
  alarm_description   = "Alarm when Alert DLQ has messages"
  comparison_operator = "GreaterThanThreshold"
  threshold           = "0"
  evaluation_periods  = "1"
  period              = "60"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  statistic           = "Sum"
  dimensions = {
    QueueName = var.alert-dlq-name
  }
  alarm_actions = [aws_sns_topic.smart-helmet-infra-alerts.arn]
}

# 6. Cloudwatch Alarm For Override DLQ
resource "aws_cloudwatch_metric_alarm" "override_dlq_alarm" {
  alarm_name          = "smart-helmet-override-dlq-alarm"
  alarm_description   = "Alarm when Override DLQ has messages"
  comparison_operator = "GreaterThanThreshold"
  threshold           = "0"
  evaluation_periods  = "1"
  period              = "60"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  statistic           = "Sum"
  dimensions = {
    QueueName = var.override-dlq-name
  }
  alarm_actions = [aws_sns_topic.smart-helmet-infra-alerts.arn]
}

# 7. Cloudwatch Alarm For DynamoDB Hot Storage
resource "aws_cloudwatch_metric_alarm" "dynamoDB-hot-storage-alarm" {
  alarm_name          = "smart-helmet-dynamodb-hot-storage-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 0
  alarm_description   = "Alarm when DynamoDB hot storage experiences Read or Write throttling"
  alarm_actions       = [aws_sns_topic.smart-helmet-infra-alerts.arn]
  
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
        TableName = var.dynamodb-hot-storage-name
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
        TableName = var.dynamodb-hot-storage-name
      }
    }
  }
}

# 8. Cloudwatch Alarm For DynamoDB Cold Storage
resource "aws_cloudwatch_metric_alarm" "dynamoDB-cold-storage-alarm" {
  alarm_name          = "smart-helmet-dynamodb-cold-storage-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 0
  alarm_description   = "Alarm when DynamoDB cold storage experiences Read or Write throttling"
  alarm_actions       = [aws_sns_topic.smart-helmet-infra-alerts.arn]

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
        TableName = var.dynamoDB-cold-storage-name
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
        TableName = var.dynamoDB-cold-storage-name
      }
    }
  }
}

# 9. Cloudwatch Alarm For DynamoDB Execution Registry
resource "aws_cloudwatch_metric_alarm" "dynamoDB-execution-registry-alarm" {
  alarm_name          = "smart-helmet-dynamodb-execution-registry-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 0
  alarm_description   = "Alarm when DynamoDB execution registry experiences Read or Write throttling"
  alarm_actions       = [aws_sns_topic.smart-helmet-infra-alerts.arn]

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
        TableName = var.dynamoDB-execution-registry-name
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
        TableName = var.dynamoDB-execution-registry-name
      }
    }
  }
}

# 10. ECS Cluster Log Group 
resource "aws_cloudwatch_log_group" "ecs_cluster_logs" {
  name              = var.ecs-log-group-name
  retention_in_days = 14
}

# 11. IOT Core Cloudwatch Logs
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
  alarm_actions       = [aws_sns_topic.smart-helmet-infra-alerts.arn]
}

# 12. Step Function Cloudwatch Metrics
resource "aws_cloudwatch_metric_alarm" "step_function_failures_alarm" {
  alarm_name          = "smart-helmet-step-function-failures-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 0
  alarm_description   = "Alarm when Step Function executions fail or timeout"
  alarm_actions       = [aws_sns_topic.smart-helmet-infra-alerts.arn]

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
        StateMachineArn = var.step-function-arn
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
        StateMachineArn = var.step-function-arn
      }
    }
  }
}

# 13. SQS ApproximateAgeOfOldestMessage Alarms
resource "aws_cloudwatch_metric_alarm" "sqs_old_message_alarm" {
  for_each            = var.queue_names
  alarm_name          = "smart-helmet-sqs-${each.key}-old-message-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateAgeOfOldestMessage"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Maximum"
  threshold           = 600
  alarm_description   = "Alarm if a message sits in the queue for more than 10 minutes"
  alarm_actions       = [aws_sns_topic.smart-helmet-infra-alerts.arn]
  dimensions = {
    QueueName = each.key
  }
}

# 14. Application Log Metric Filter for ERRORs
resource "aws_cloudwatch_log_metric_filter" "ecs_error_filter" {
  name           = "smart-helmet-ecs-error-filter"
  pattern        = "ERROR"
  log_group_name = aws_cloudwatch_log_group.ecs_cluster_logs.name

  metric_transformation {
    name      = "ApplicationErrorCount"
    namespace = "SmartHelmet/ApplicationLogs"
    value     = "1"
  }
}

# 15. CloudWatch Alarm for the Application Error Filter
resource "aws_cloudwatch_metric_alarm" "ecs_error_alarm" {
  alarm_name          = "smart-helmet-ecs-error-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = aws_cloudwatch_log_metric_filter.ecs_error_filter.metric_transformation[0].name
  namespace           = aws_cloudwatch_log_metric_filter.ecs_error_filter.metric_transformation[0].namespace
  period              = 60
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "Alarm when Python logs 'ERROR' more than 5 times in a minute"
  alarm_actions       = [aws_sns_topic.smart-helmet-infra-alerts.arn]
}

# 16. ECS Cluster Memory Utilization Alarm
resource "aws_cloudwatch_metric_alarm" "ecs_memory_alarm" {
  alarm_name          = "smart-helmet-ecs-memory-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 90
  alarm_description   = "Alarm when ECS Cluster Memory goes above 90%"
  alarm_actions       = [aws_sns_topic.smart-helmet-infra-alerts.arn]
  dimensions = {
    ClusterName = "smart-helmet-cluster"
  }
}
