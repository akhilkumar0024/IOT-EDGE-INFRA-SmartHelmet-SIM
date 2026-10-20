resource "aws_cloudwatch_dashboard" "observability" {
  dashboard_name = "smart-helmet-observability"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 8
        height = 6
        properties = {
          title   = "ECS CPU utilisation (%)"
          region  = var.region
          view    = "timeSeries"
          period  = 300
          stat    = "Average"
          metrics = local.dashboard_ecs_cpu
          yAxis   = { left = { min = 0, max = 100 } }
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 0
        width  = 8
        height = 6
        properties = {
          title   = "ECS memory utilisation (%)"
          region  = var.region
          view    = "timeSeries"
          period  = 300
          stat    = "Average"
          metrics = local.dashboard_ecs_memory
          yAxis   = { left = { min = 0, max = 100 } }
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 0
        width  = 8
        height = 6
        properties = {
          title   = "ECS tasks: running vs desired"
          region  = var.region
          view    = "timeSeries"
          period  = 300
          stat    = "Average"
          metrics = local.dashboard_ecs_tasks
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title   = "Queue depth (messages visible)"
          region  = var.region
          view    = "timeSeries"
          period  = 300
          stat    = "Average"
          metrics = local.dashboard_queue_depth
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title   = "Dead-letter queues (anything above zero is a defect)"
          region  = var.region
          view    = "timeSeries"
          period  = 300
          stat    = "Sum"
          metrics = local.dashboard_dlq_depth
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6
        properties = {
          title   = "Age of oldest message (seconds)"
          region  = var.region
          view    = "timeSeries"
          period  = 300
          stat    = "Maximum"
          metrics = local.dashboard_queue_age
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 12
        width  = 12
        height = 6
        properties = {
          title   = "Step Functions executions"
          region  = var.region
          view    = "timeSeries"
          period  = 300
          stat    = "Sum"
          metrics = local.dashboard_step_functions
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 18
        width  = 24
        height = 6
        properties = {
          title   = "IoT Core"
          region  = var.region
          view    = "timeSeries"
          period  = 300
          stat    = "Sum"
          metrics = local.dashboard_iot
        }
      },
      {
        type   = "alarm"
        x      = 0
        y      = 24
        width  = 24
        height = 8
        properties = {
          title  = "Alarm status"
          alarms = local.dashboard_alarms
        }
      },
    ]
  })
}

locals {
  dashboard_ecs_cpu = [
    for name, service in local.ecs_services : [
      "AWS/ECS", "CPUUtilization",
      "ClusterName", data.aws_ssm_parameter.ecs_cluster_name.value,
      "ServiceName", service,
      { label = name },
    ]
  ]

  dashboard_ecs_memory = [
    for name, service in local.ecs_services : [
      "AWS/ECS", "MemoryUtilization",
      "ClusterName", data.aws_ssm_parameter.ecs_cluster_name.value,
      "ServiceName", service,
      { label = name },
    ]
  ]

  dashboard_ecs_tasks = concat(
    [
      for name, service in local.ecs_services : [
        "ECS/ContainerInsights", "RunningTaskCount",
        "ClusterName", data.aws_ssm_parameter.ecs_cluster_name.value,
        "ServiceName", service,
        { label = "${name} running" },
      ]
    ],
    [
      for name, service in local.ecs_services : [
        "ECS/ContainerInsights", "DesiredTaskCount",
        "ClusterName", data.aws_ssm_parameter.ecs_cluster_name.value,
        "ServiceName", service,
        { label = "${name} desired" },
      ]
    ],
  )

  dashboard_queue_depth = [
    for name, queue in local.queue_map : [
      "AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", queue, { label = name },
    ]
  ]

  dashboard_dlq_depth = [
    for name, queue in local.dlq_map : [
      "AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", queue, { label = name },
    ]
  ]

  dashboard_queue_age = [
    for name, queue in local.queue_map : [
      "AWS/SQS", "ApproximateAgeOfOldestMessage", "QueueName", queue, { label = name },
    ]
  ]

  dashboard_step_function_arns = {
    "alert"          = data.aws_ssm_parameter.alert_state_machine_arn.value
    "reconciliation" = data.aws_ssm_parameter.reconciliation_state_machine_arn.value
  }

  # setproduct rather than nested for: `flatten` recurses all the way down and
  # would split each metric array into loose strings, which CloudWatch rejects.
  dashboard_step_functions = [
    for pair in setproduct(keys(local.dashboard_step_function_arns), ["ExecutionsSucceeded", "ExecutionsFailed", "ExecutionsTimedOut", "ExecutionsStarted"]) : [
      "AWS/States", pair[1],
      "StateMachineArn", local.dashboard_step_function_arns[pair[0]],
      { label = "${pair[0]} ${pair[1]}" },
    ]
  ]

  dashboard_iot = [
    ["AWS/IoT", "RulesExecuted", { label = "rules executed" }],
    ["AWS/IoT", "PublishIn.Success", "Protocol", "MQTT", { label = "publish-in (MQTT)" }],
    ["AWS/IoT", "TopicMatch", "RuleName", "iot_telemetry_data_rule", { label = "matches: telemetry rule" }],
    ["AWS/IoT", "CloudwatchLogs:PutLogEventsFailed", "LogGroup", "AWSIotLogsV2", { label = "log delivery failures" }],
  ]

  dashboard_alarms = concat(
    [for a in aws_cloudwatch_metric_alarm.dlq_alarms : a.arn],
    [for a in aws_cloudwatch_metric_alarm.dynamodb_throttle_alarms : a.arn],
    [aws_cloudwatch_metric_alarm.iot_core_throttling_alarm.arn],
    [aws_cloudwatch_metric_alarm.step_function_failures_alarm.arn],
    [for a in aws_cloudwatch_metric_alarm.sqs_old_message_alarm : a.arn],
    [aws_cloudwatch_metric_alarm.ecs_error_alarm.arn],
    [aws_cloudwatch_metric_alarm.ecs_memory_alarm.arn],
    [for a in aws_cloudwatch_metric_alarm.ecs_tasks_below_desired : a.arn],
    [for a in aws_cloudwatch_metric_alarm.ecs_cpu_saturation : a.arn],
    [for a in aws_cloudwatch_metric_alarm.ecs_service_memory_alarm : a.arn],
  )
}