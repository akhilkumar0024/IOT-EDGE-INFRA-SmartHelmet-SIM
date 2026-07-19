# 1. Emergency Alerts SNS Topic
resource "aws_sns_topic" "smart-helmet-emergency-alerts" {
  name = "emergency-alerts-topic"
}

# 2. IAM Role for the Step Functions
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

# 3. Policies Allowing Step Functions to access DynamoDB, SNS, and IoT Core
resource "aws_iam_policy" "step-functions-policy" {
  name = "alert-infra-step-functions-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query"
        ]
        Resource = [
          var.cold-storage-arn,
          var.execution-registry-arn
        ]
      },
      {
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = aws_sns_topic.smart-helmet-emergency-alerts.arn
      },
      {
        Effect   = "Allow"
        Action   = "iot:Publish"
        Resource = "arn:aws:iot:*:*:topic/helmet/*/alert/status"
      }
    ]
  })
}

# 4. Role Policy Attachment
resource "aws_iam_policy_attachment" "step-functions-policy-attach" {
  name       = "alert-infra-step-functions-policy-attach"
  policy_arn = aws_iam_policy.step-functions-policy.arn
  roles      = [aws_iam_role.state_machine_execution_role.name]
}

# 5. SFN1 / SFN3: The Alert Countdown State Machine
resource "aws_sfn_state_machine" "alert_state_machine" {
  name     = "SmartHelmetAlertWorkflow"
  role_arn = aws_iam_role.state_machine_execution_role.arn
  definition = jsonencode({
    Comment = "State Machine for handling Smart Helmet Alert Countdowns."
    StartAt = "WaitWindow"
    States = {
      WaitWindow = {
        Type        = "Wait"
        SecondsPath = "$.wait_seconds"
        Next        = "ReadExecutionRegistry"
      }
      ReadExecutionRegistry = {
        Type     = "Task"
        Resource = "arn:aws:states:::dynamodb:getItem"
        Parameters = {
          TableName = var.execution-registry-name
          Key = {
            "helmetId" = { "S.$" = "$.helmet_id" }
          }
        }
        ResultPath = "$.execution_registry"
        Next       = "VerifyLease"
      }
      VerifyLease = {
        Type = "Choice"
        Choices = [
          {
            "And" : [
              {
                "Variable" : "$.execution_registry.Item",
                "IsPresent" : true
              },
              {
                "Variable" : "$.execution_registry.Item.ExecutionArn.S",
                "IsPresent" : true
              },
              {
                "Variable" : "$.execution_registry.Item.ExecutionArn.S",
                "StringEqualsPath" : "$$.Execution.Id"
              }
            ],
            "Next" : "CheckStatus"
          }
        ]
        Default = "SilentExit"
      }
      CheckStatus = {
        Type = "Choice"
        Choices = [
          {
            "Variable" : "$.execution_registry.Item.status.S",
            "StringEquals" : "CANCEL",
            "Next" : "WriteColdStorageCancelled"
          },
          {
            "Variable" : "$.execution_registry.Item.status.S",
            "StringEquals" : "FP_CD",
            "Next" : "WriteColdStorageFPDismissed"
          }
        ]
        Default = "SendSNSEmergencyAlert"
      }
      SendSNSEmergencyAlert = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn = aws_sns_topic.smart-helmet-emergency-alerts.arn
          Message = {
            "helmetId.$"  = "$.helmet_id"
            "timestamp.$" = "$.timestamp"
            "status"      = "INCIDENT_CONFIRMED"
            "message"     = "Emergency Alert: A crash has been confirmed for the rider."
          }
        }
        ResultPath = "$.sns_result"
        Next       = "WriteColdStorageConfirmed"
      }
      WriteColdStorageCancelled = {
        Type     = "Task"
        Resource = "arn:aws:states:::dynamodb:putItem"
        Parameters = {
          TableName = var.cold-storage-name
          Item = {
            "helmetId"  = { "S.$" = "$.helmet_id" }
            "timestamp" = { "N.$" = "States.Format('{}', $.timestamp)" }
            "Status"    = { "S" = "INCIDENT_CANCELLED" }
          }
        }
        Next = "DeleteExecutionRegistry"
      }
      WriteColdStorageFPDismissed = {
        Type     = "Task"
        Resource = "arn:aws:states:::dynamodb:putItem"
        Parameters = {
          TableName = var.cold-storage-name
          Item = {
            "helmetId"  = { "S.$" = "$.helmet_id" }
            "timestamp" = { "N.$" = "States.Format('{}', $.timestamp)" }
            "Status"    = { "S" = "FALSE_POSITIVE_DISMISSED" }
          }
        }
        Next = "DeleteExecutionRegistry"
      }
      WriteColdStorageConfirmed = {
        Type     = "Task"
        Resource = "arn:aws:states:::dynamodb:putItem"
        Parameters = {
          TableName = var.cold-storage-name
          Item = {
            "helmetId"  = { "S.$" = "$.helmet_id" }
            "timestamp" = { "N.$" = "States.Format('{}', $.timestamp)" }
            "Status"    = { "S" = "INCIDENT_CONFIRMED" }
          }
        }
        Next = "DeleteExecutionRegistry"
      }
      DeleteExecutionRegistry = {
        Type     = "Task"
        Resource = "arn:aws:states:::dynamodb:deleteItem"
        Parameters = {
          TableName = var.execution-registry-name
          Key = {
            "helmetId" = { "S.$" = "$.helmet_id" }
          }
        }
        End = true
      }
      SilentExit = {
        Type = "Pass"
        End  = true
      }
    }
  })
}

# 6. SFN2: The Reconciliation State Machine
resource "aws_sfn_state_machine" "reconciliation_state_machine" {
  name     = "SmartHelmetReconciliationWorkflow"
  role_arn = aws_iam_role.state_machine_execution_role.arn
  definition = jsonencode({
    Comment = "State Machine for handling late alert reconciliation."
    StartAt = "DeleteExecutionRegistry"
    States = {
      DeleteExecutionRegistry = {
        Type     = "Task"
        Resource = "arn:aws:states:::dynamodb:deleteItem"
        Parameters = {
          TableName = var.execution-registry-name
          Key = {
            "helmetId" = { "S.$" = "$.helmet_id" }
          }
        }
        Next = "QueryColdStorage"
      }
      QueryColdStorage = {
        Type     = "Task"
        Resource = "arn:aws:states:::dynamodb:query"
        Parameters = {
          TableName              = var.cold-storage-name
          KeyConditionExpression = "helmetId = :h"
          ExpressionAttributeValues = {
            ":h" = { "S.$" = "$.helmet_id" }
          }
          ScanIndexForward = false
          Limit            = 1
        }
        ResultPath = "$.query_result"
        Next       = "EvaluateReconciliation"
      }
      EvaluateReconciliation = {
        Type = "Choice"
        Choices = [
          {
            "Variable"      = "$.is_reconcilable"
            "BooleanEquals" = true
            "Next"          = "SendSNSStandDown"
          }
        ]
        Default = "SilentExit"
      }
      SendSNSStandDown = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn = aws_sns_topic.smart-helmet-emergency-alerts.arn
          Message = {
            "helmetId.$" = "$.helmet_id"
            "status"     = "RESOLVED_BY_LATE_CANCEL"
            "message"    = "Emergency Stand-down: The rider cancelled the emergency alert."
          }
        }
        ResultPath = "$.sns_result"
        Next       = "UpdateColdStorageCancelled"
      }
      UpdateColdStorageCancelled = {
        Type     = "Task"
        Resource = "arn:aws:states:::dynamodb:putItem"
        Parameters = {
          TableName = var.cold-storage-name
          Item = {
            "helmetId"  = { "S.$" = "$.helmet_id" }
            "timestamp" = { "N.$" = "States.Format('{}', $.timestamp)" }
            "Status"    = { "S" = "RESOLVED_BY_LATE_CANCEL" }
          }
        }
        End = true
      }
      SilentExit = {
        Type = "Pass"
        End  = true
      }
    }
  })
}

