# Alert Handler IAM Role
resource "aws_iam_role" "alert_role" {
  name = "smart-helmet-alert-infra-role"

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
    Name = "smart-helmet-alert-infra-role"
  }
}

# Alert Handler IAM Policy
resource "aws_iam_policy" "alert_policy" {
  name        = "smart-helmet-alert-infra-policy"
  description = "Scoped policy for Alert Handler microservice"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AccessAlertAndOverrideQueues"
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = [
          data.aws_ssm_parameter.alert_queue_arn.value,
          data.aws_ssm_parameter.override_queue_arn.value
        ]
      },
      {
        Sid    = "WriteReadExecutionRegistry"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem"
        ]
        Resource = data.aws_ssm_parameter.execution_registry_arn.value
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
          data.aws_ssm_parameter.alert_state_machine_arn.value,
          data.aws_ssm_parameter.reconciliation_state_machine_arn.value
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

resource "aws_iam_role_policy_attachment" "alert_attach" {
  role       = aws_iam_role.alert_role.name
  policy_arn = aws_iam_policy.alert_policy.arn
}
