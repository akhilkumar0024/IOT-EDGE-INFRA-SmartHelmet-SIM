# aws_iot_logging_options maps to the V2 logging API (SetV2LoggingOptions), so
# events are written as JSON to the `AWSIotLogsV2` log group.
#
# Rate-sensitive: AWS asks for logging to be disabled during sustained load
# tests, and the service may switch it off automatically if the account is
# throttled.

# Owned here rather than left to IoT's `logs:CreateLogGroup` so that retention
# gets set. CloudWatch defaults to never-expire; 30 days matches the ECS group.
resource "aws_cloudwatch_log_group" "iot_logs" {
  name              = "AWSIotLogsV2"
  retention_in_days = 30
}

# Separate from iot_sqs_role so each IoT role carries only its own permission.
resource "aws_iam_role" "iot_logging_role" {
  name        = "smart-helmet-iot-logging-role"
  description = "Allows AWS IoT Core to write IoT log events to CloudWatch Logs"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "iot.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "smart-helmet-iot-logging-role"
  }
}

resource "aws_iam_policy" "iot_logging_policy" {
  name        = "smart-helmet-iot-logging-policy"
  description = "Write AWS IoT log events to the AWSIotLogsV2 log group"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.iot_logs.arn}:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "iot_logging_attach" {
  role       = aws_iam_role.iot_logging_role.name
  policy_arn = aws_iam_policy.iot_logging_policy.arn
}

resource "aws_iot_logging_options" "this" {
  default_log_level = "INFO"
  role_arn          = aws_iam_role.iot_logging_role.arn

  # AWS accepts the role ARN without validating it, so without this the option
  # can be written before the policy exists and no log stream is ever created.
  depends_on = [aws_iam_role_policy_attachment.iot_logging_attach]
}
