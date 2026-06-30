#1. SNS Topic
resource "aws_sns_topic" "smart-helmet-infra-alerts" {
  name = "user-updates-topic"
}

#2.SNS Subscription
resource "aws_sns_topic_subscription" "smart-helmet-infra-alerts" {
  topic_arn = aws_sns_topic.smart-helmet-infra-alerts.arn
  protocol  = "email"
  endpoint  = var.sns-email-address
}

#1.Cloudwatch Alarm For Telemetry DLQ
resource "aws_cloudwatch_metric_alarm" "telemetry_dlq_alarm" {
  alarm_name        = "Telemetry-DLQ-Messages-Visible"
  alarm_description = "Alarm when Telemetry DLQ has messages"

  # Trigger the alarm if the metric is > 0
  comparison_operator = "GreaterThanThreshold"
  threshold           = "0"

  # Look at the metric once every 60 seconds (1 period of 60s)
  evaluation_periods = "1"
  period             = "60"

  # The specific AWS Metric we are watching
  namespace   = "AWS/SQS"
  metric_name = "ApproximateNumberOfMessagesVisible"
  statistic   = "Sum"

  # How AWS knows WHICH queue to look at
  dimensions = {
    QueueName = var.telemetry-dlq-name
  }

  # When the alarm goes off, send a message to the SNS megaphone
  alarm_actions = [aws_sns_topic.smart-helmet-infra-alerts.arn]
}

#2.Cloudwatch Alarm For Control DLQ
resource "aws_cloudwatch_metric_alarm" "control_dlq_alarm" {
  alarm_name          = "Control-DLQ-Messages-Visible"
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

#3.Cloudwatch Alarm For LWT DLQ
resource "aws_cloudwatch_metric_alarm" "lwt_dlq_alarm" {
  alarm_name          = "LWT-DLQ-Messages-Visible"
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

#4.Cloudwatch Alarm For Crash DLQ
resource "aws_cloudwatch_metric_alarm" "crash_dlq_alarm" {
  alarm_name          = "Crash-DLQ-Messages-Visible"
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

#5.Cloudwatch Alarm For Alert DLQ
resource "aws_cloudwatch_metric_alarm" "alert_dlq_alarm" {
  alarm_name          = "Alert-DLQ-Messages-Visible"
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

#6.Cloudwatch Alarm For Override DLQ
resource "aws_cloudwatch_metric_alarm" "override_dlq_alarm" {
  alarm_name          = "Override-DLQ-Messages-Visible"
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
