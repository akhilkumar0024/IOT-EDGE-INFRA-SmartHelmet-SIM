# Telemetry Service IAM Role
resource "aws_iam_role" "telemetry_role" {
  name = "smart-helmet-telemetry-infra-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "smart-helmet-telemetry-infra-role"
  }
}

# Telemetry Service IAM Policy
resource "aws_iam_policy" "telemetry_policy" {
  name        = "smart-helmet-telemetry-infra-policy"
  description = "Scoped policy for Telemetry Processor microservice"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AccessTelemetryQueue"
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = data.aws_ssm_parameter.telemetry_queue_arn.value
      },
      {
        Sid    = "AllowWriteCrashQueue"
        Effect = "Allow"
        Action = [
          "sqs:SendMessage"
        ]
        Resource = data.aws_ssm_parameter.crash_queue_arn.value
      },
      {
        Sid    = "AllowWriteHotStorage"
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:BatchWriteItem"
        ]
        Resource = data.aws_ssm_parameter.hot_storage_arn.value
      },
      {
        Sid    = "AllowReadParameterStore"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParametersByPath",
          "ssm:GetParameters"
        ]
        Resource = "arn:aws:ssm:*:*:parameter/smart-helmet/config/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "telemetry_attach" {
  role       = aws_iam_role.telemetry_role.name
  policy_arn = aws_iam_policy.telemetry_policy.arn
}
