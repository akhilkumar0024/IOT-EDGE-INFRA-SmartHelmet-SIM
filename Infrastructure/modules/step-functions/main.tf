#1.IAM Role for the step function
resource "aws_iam_role" "state_machine_execution_role" {
  name = "alert-infra-step-function-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "states.amazonaws.com"
        }
      }
    ]
  })
}

#2.Policies Allowing Step Function to access Execution Registry and IOT Core
resource "aws_iam_policy" "step-functions-policy" {
  name = "alert-infra-step-functions-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:DeleteItem"
        ]
        Resource = [
          var.cold-storage-arn,
          var.execution-registry-arn
        ]
      },
      {
        Effect   = "Allow"
        Action   = "iot:Publish"
        Resource = "arn:aws:iot:*:*:topic/helmet/*/alert/status"
      }
    ]
  })
}

#3.Role Policy Attachment
resource "aws_iam_policy_attachment" "step-functions-policy-attach" {
  name       = "alert-infra-step-functions-policy-attach"
  policy_arn = aws_iam_policy.step-functions-policy.arn
  roles      = [aws_iam_role.state_machine_execution_role.name]
}

#4.The Alert Infra Step Function State Machine
resource "aws_sfn_state_machine" "alert_state_machine" {
  name     = "SmartHelmetAlertWorkflow"
  role_arn = aws_iam_role.state_machine_execution_role.arn
  definition = jsonencode({
    Comment = "State Machine for handling Smart Helmet Alert Countdowns. IoT publish is handled by the Alert Infra Python app before starting this execution."
    StartAt = "WaitWindow"
    States = {
      WaitWindow = {
        Type        = "Wait"
        SecondsPath = "$.wait_seconds"
        Next        = "WriteColdStorage"
      }
      WriteColdStorage = {
        Type     = "Task"
        Resource = "arn:aws:states:::dynamodb:putItem"
        Parameters = {
          TableName = var.cold-storage-name
          Item = {
            "helmetId"  = { "S.$" = "$.helmet_id" }
            "timestamp" = { "N.$" = "States.Format('{}', $.timestamp)" }
            "Status"    = { "S" = "CONFIRMED_BY_TIMEOUT" }
          }
        }
        End = true
      }
    }
  })
}

