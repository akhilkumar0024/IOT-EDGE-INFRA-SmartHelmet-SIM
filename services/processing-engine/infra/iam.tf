# Processing Engine IAM Role
resource "aws_iam_role" "processing_role" {
  name = "smart-helmet-processing-infra-role"

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
    Name = "smart-helmet-processing-infra-role"
  }
}

# Processing Engine IAM Policy
resource "aws_iam_policy" "processing_policy" {
  name        = "smart-helmet-processing-infra-policy"
  description = "Scoped policy for Processing Engine microservice"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AccessControlCrashLWTQueues"
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = [
          data.aws_ssm_parameter.control_queue_arn.value,
          data.aws_ssm_parameter.crash_queue_arn.value,
          data.aws_ssm_parameter.lwt_queue_arn.value
        ]
      },
      {
        Sid    = "AllowWriteAlertQueue"
        Effect = "Allow"
        Action = [
          "sqs:SendMessage"
        ]
        Resource = [
          data.aws_ssm_parameter.alert_queue_arn.value
        ]
      },
      {
        Sid    = "AllowWriteColdDynamoDB"
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem"
        ]
        Resource = data.aws_ssm_parameter.cold_storage_arn.value
      },
      {
        Sid    = "AllowReadHotDynamoDB"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = data.aws_ssm_parameter.hot_storage_arn.value
      },
      {
        Sid    = "AllowReadWriteDeviceStatusDB"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ]
        Resource = data.aws_ssm_parameter.device_status_table_arn.value
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

resource "aws_iam_role_policy_attachment" "processing_attach" {
  role       = aws_iam_role.processing_role.name
  policy_arn = aws_iam_policy.processing_policy.arn
}
