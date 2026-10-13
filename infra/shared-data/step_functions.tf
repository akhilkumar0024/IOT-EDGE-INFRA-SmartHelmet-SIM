resource "aws_sns_topic" "emergency_alerts" {
  name = "smart-helmet-emergency-alerts-topic"

  tags = {
    Name = "smart-helmet-emergency-alerts-topic"
  }
}

resource "aws_iam_role" "step_functions_role" {
  name = "smart-helmet-step-function-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "states.amazonaws.com" }
    }]
  })
}

resource "aws_iam_policy" "step_functions_policy" {
  name = "smart-helmet-step-function-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem"]
        Resource = [
          aws_dynamodb_table.cold_storage.arn,
          aws_dynamodb_table.execution_registry.arn
        ]
      },
      {
        Effect   = "Allow"
        Action   = "ses:SendEmail"
        Resource = "arn:aws:ses:*:*:identity/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "step_functions_attach" {
  role       = aws_iam_role.step_functions_role.name
  policy_arn = aws_iam_policy.step_functions_policy.arn
}

resource "aws_sfn_state_machine" "alert_state_machine" {
  name     = "SmartHelmetAlertWorkflow"
  role_arn = aws_iam_role.step_functions_role.arn

  definition = jsonencode({
    Comment = "Idempotent alert countdown using a composite incident key."
    StartAt = "WaitWindow"
    States = {
      WaitWindow = {
        Type        = "Wait"
        SecondsPath = "$.wait_seconds"
        Next        = "ReadRegistry"
      }
      ReadRegistry = {
        Type     = "Task"
        Resource = "arn:aws:states:::dynamodb:getItem"
        Parameters = {
          TableName = aws_dynamodb_table.execution_registry.name
          Key = {
            helmetId   = { "S.$" = "$.helmet_id" }
            incidentId = { "S.$" = "$.incident_id" }
          }
        }
        ResultPath = "$.registry"
        Next       = "CheckRegistryState"
      }
      CheckRegistryState = {
        Type = "Choice"
        Choices = [
          {
            And = [
              { Variable = "$.registry.Item.incidentId.S", IsPresent = true },
              { Variable = "$.registry.Item.incidentId.S", StringEqualsPath = "$.incident_id" },
              { Variable = "$.registry.Item.status.S", StringEquals = "CANCELLED" }
            ]
            Next = "WriteCancelledIncident"
          },
          {
            And = [
              { Variable = "$.registry.Item.incidentId.S", IsPresent = true },
              { Variable = "$.registry.Item.incidentId.S", StringEqualsPath = "$.incident_id" },
              { Variable = "$.registry.Item.status.S", StringEquals = "COUNTDOWN_ACTIVE" }
            ]
            Next = "ConfirmRegistry"
          }
        ]
        Default = "SilentExit"
      }
      ConfirmRegistry = {
        Type     = "Task"
        Resource = "arn:aws:states:::dynamodb:updateItem"
        Parameters = {
          TableName = aws_dynamodb_table.execution_registry.name
          Key = {
            helmetId   = { "S.$" = "$.helmet_id" }
            incidentId = { "S.$" = "$.incident_id" }
          }
          UpdateExpression    = "SET #status = :confirmed"
          ConditionExpression = "#status = :active"
          ExpressionAttributeNames = { "#status" = "status" }
          ExpressionAttributeValues = {
            ":confirmed" = { "S" = "CONFIRMED" }
            ":active"    = { "S" = "COUNTDOWN_ACTIVE" }
          }
        }
        ResultPath = null
        Next       = "WriteConfirmedIncident"
      }
      WriteCancelledIncident = {
        Type     = "Task"
        Resource = "arn:aws:states:::dynamodb:putItem"
        Parameters = {
          TableName = aws_dynamodb_table.cold_storage.name
          Item = {
            helmetId   = { "S.$" = "$.helmet_id" }
            timestamp  = { "N.$" = "States.Format('{}', $.incident_timestamp)" }
            incidentId = { "S.$" = "$.incident_id" }
            Status     = { "S" = "INCIDENT_CANCELLED" }
          }
        }
        ResultPath = null
        End        = true
      }
      WriteConfirmedIncident = {
        Type     = "Task"
        Resource = "arn:aws:states:::dynamodb:putItem"
        Parameters = {
          TableName = aws_dynamodb_table.cold_storage.name
          Item = {
            helmetId   = { "S.$" = "$.helmet_id" }
            timestamp  = { "N.$" = "States.Format('{}', $.incident_timestamp)" }
            incidentId = { "S.$" = "$.incident_id" }
            Status     = { "S" = "INCIDENT_CONFIRMED" }
          }
        }
        ResultPath = null
        Next       = "SendAdminAlert"
      }
      SendAdminAlert = {
        Type     = "Task"
        Resource = "arn:aws:states:::aws-sdk:ses:sendEmail"
        Parameters = {
          Destination = { ToAddresses = [var.sns-email-address] }
          Message = {
            Subject = { "Data.$" = "States.Format('Smart Helmet incident {} confirmed', $.incident_id)" }
            Body = { Text = { "Data.$" = "States.Format('Confirmed incident for helmet {}.', $.helmet_id)" } }
          }
          Source = var.sns-email-address
        }
        ResultPath = null
        End        = true
      }
      SilentExit = { Type = "Pass", End = true }
    }
  })
}

resource "aws_sfn_state_machine" "reconciliation_state_machine" {
  name     = "SmartHelmetReconciliationWorkflow"
  role_arn = aws_iam_role.step_functions_role.arn

  definition = jsonencode({
    Comment = "Idempotent late-cancellation reconciliation."
    StartAt = "IsReconciliable"
    States = {
      IsReconciliable = {
        Type = "Choice"
        Choices = [{
          Variable      = "$.is_reconcilable"
          BooleanEquals = true
          Next          = "MarkResolved"
        }]
        Default = "SilentExit"
      }
      MarkResolved = {
        Type     = "Task"
        Resource = "arn:aws:states:::dynamodb:updateItem"
        Parameters = {
          TableName = aws_dynamodb_table.cold_storage.name
          Key = {
            helmetId  = { "S.$" = "$.helmet_id" }
            timestamp = { "N.$" = "States.Format('{}', $.incident_timestamp)" }
          }
          UpdateExpression    = "SET #status = :resolved"
          ConditionExpression = "incidentId = :incident_id AND #status = :confirmed"
          ExpressionAttributeNames = { "#status" = "Status" }
          ExpressionAttributeValues = {
            ":incident_id" = { "S.$" = "$.incident_id" }
            ":confirmed"   = { "S" = "INCIDENT_CONFIRMED" }
            ":resolved"    = { "S" = "RESOLVED_BY_LATE_CANCEL" }
          }
        }
        ResultPath = null
        Next       = "SendStandDown"
      }
      SendStandDown = {
        Type     = "Task"
        Resource = "arn:aws:states:::aws-sdk:ses:sendEmail"
        Parameters = {
          Destination = { ToAddresses = [var.sns-email-address] }
          Message = {
            Subject = { "Data.$" = "States.Format('Smart Helmet incident {} resolved', $.incident_id)" }
            Body = { Text = { "Data.$" = "States.Format('Late cancellation accepted for helmet {}.', $.helmet_id)" } }
          }
          Source = var.sns-email-address
        }
        ResultPath = null
        End        = true
      }
      SilentExit = { Type = "Pass", End = true }
    }
  })
}
