# 1. Telemetry infra IAM Role
resource "aws_iam_role" "Telemetry-Infra-Role" {
  name = "smart-helmet-telemetry-infra-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      },
    ]
  })

  tags = {
    Name = "smart-helmet-telemetry-infra-role"
  }
}

# 1. Telemetry infra IAM Policy
resource "aws_iam_policy" "Telemetry-Infra-Role-Policy" {
  name        = "smart-helmet-telemetry-infra-policy"
  description = "Policy for telemetry infra"

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
        Resource = var.telemetry-queue-arn
      },
      {
        Sid    = "AllowWriteOtherQueues"
        Effect = "Allow"
        Action = [
          "sqs:SendMessage"
        ]
        Resource = [
          var.crash-queue-arn,
        ]
      },
      {
        Sid    = "AllowWriteDynamoDB"
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:BatchWriteItem"
        ]
        Resource = var.hot-storage-arn
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

# 1. Attach Telemetry infra role to policy
resource "aws_iam_role_policy_attachment" "Telemetry-Infra-Role-Policy-Attachment" {
  role       = aws_iam_role.Telemetry-Infra-Role.name
  policy_arn = aws_iam_policy.Telemetry-Infra-Role-Policy.arn
}

# 2. Processing Infra IAM Role
resource "aws_iam_role" "Processing-Infra-Role" {
  name = "smart-helmet-processing-infra-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      },
    ]
  })

  tags = {
    Name = "smart-helmet-processing-infra-role"
  }
}

# 2. Processing Infra IAM Policy
resource "aws_iam_policy" "Processing-Infra-Role-Policy" {
  name        = "smart-helmet-processing-infra-policy"
  description = "Policy for processing infra"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AccessControlCrashQueue"
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = [
          var.control-queue-arn,
          var.crash-queue-arn,
          var.LWT-queue-arn
        ]
      },
      {
        Sid    = "AllowWriteAlertQueue"
        Effect = "Allow"
        Action = [
          "sqs:SendMessage"
        ]
        Resource = [
          var.alert-queue-arn
        ]
      },
      {
        Sid    = "AllowWriteColdDynamoDB"
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem"
        ]
        Resource = var.cold-storage-arn
      },
      {
        Sid    = "AllowReadHotDynamoDB"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = var.hot-storage-arn
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
        Resource = var.device-status-db-table-arn
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

# 2. Attach Processing infra role to policy
resource "aws_iam_role_policy_attachment" "Processing-Infra-Role-Policy-Attachment" {
  role       = aws_iam_role.Processing-Infra-Role.name
  policy_arn = aws_iam_policy.Processing-Infra-Role-Policy.arn
}

# 3. Alert Infra IAM Role
resource "aws_iam_role" "Alert-Infra-Role" {
  name = "smart-helmet-alert-infra-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      },
    ]
  })

  tags = {
    Name = "smart-helmet-alert-infra-role"
  }
}

# 3. Alert Infra IAM Policy
resource "aws_iam_policy" "Alert-Infra-Role-Policy" {
  name        = "smart-helmet-alert-infra-policy"
  description = "Policy for alert infra"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AccessAlertQueue"
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = [
          var.alert-queue-arn,
          var.override-queue-arn
        ]
      },
      {
        Sid    = "WriteReadFromExecutionRegistry"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem"
        ]
        Resource = var.execution-registry-arn
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
      },
      {
        Sid    = "TriggerStepFunctions"
        Effect = "Allow"
        Action = [
          "states:StartExecution",
          "states:StopExecution"
        ]
        Resource = [
          var.step_function_arn,
          var.reconciliation_step_function_arn
        ]
      },
      {
        Sid      = "PublishToHelmet"
        Effect   = "Allow"
        Action   = "iot:Publish"
        Resource = "arn:aws:iot:*:*:topic/helmet/*/alert/status"
      }
    ]
  })
}

# 3. Attach Alert infra role to policy
resource "aws_iam_role_policy_attachment" "Alert-Infra-Role-Policy-Attachment" {
  role       = aws_iam_role.Alert-Infra-Role.name
  policy_arn = aws_iam_policy.Alert-Infra-Role-Policy.arn
}

# 4. ECS Task Execution Role (Used by ECS to pull images and write logs)
resource "aws_iam_role" "ECS-Execution-Role" {
  name = "smart-helmet-ecs-execution-role"

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
}

# 4. Attach the AWS Managed Policy for ECS Execution
resource "aws_iam_role_policy_attachment" "ECS-Execution-Role-Policy-Attachment" {
  role       = aws_iam_role.ECS-Execution-Role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
