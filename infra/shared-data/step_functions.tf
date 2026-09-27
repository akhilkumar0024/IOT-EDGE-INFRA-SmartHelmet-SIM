# 1. Emergency Alerts SNS Topic
resource "aws_sns_topic" "emergency_alerts" {
  name = "smart-helmet-emergency-alerts-topic"

  tags = {
    Name = "smart-helmet-emergency-alerts-topic"
  }
}

# 2. IAM Role for Step Functions
resource "aws_iam_role" "step_functions_role" {
  name = "smart-helmet-step-function-role"

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

  tags = {
    Name = "smart-helmet-step-function-role"
  }
}

# 3. IAM Policy for Step Functions Execution
resource "aws_iam_policy" "step_functions_policy" {
  name = "smart-helmet-step-function-policy"

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
          aws_dynamodb_table.cold_storage.arn,
          aws_dynamodb_table.execution_registry.arn
        ]
      },
      {
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = aws_sns_topic.emergency_alerts.arn
      },
      {
        Effect   = "Allow"
        Action   = "ses:SendEmail"
        Resource = "arn:aws:ses:*:*:identity/*"
      },
      {
        Effect   = "Allow"
        Action   = "iot:Publish"
        Resource = "arn:aws:iot:*:*:topic/helmet/*/alert/status"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "step_functions_attach" {
  role       = aws_iam_role.step_functions_role.name
  policy_arn = aws_iam_policy.step_functions_policy.arn
}

# 4. Emergency Alert Countdown State Machine (SFN1 / SFN3)
resource "aws_sfn_state_machine" "alert_state_machine" {
  name     = "SmartHelmetAlertWorkflow"
  role_arn = aws_iam_role.step_functions_role.arn

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
          TableName = aws_dynamodb_table.execution_registry.name
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
            "Variable"     : "$.execution_registry.Item.status.S",
            "StringEquals" : "CANCEL",
            "Next"         : "WriteColdStorageCancelled"
          },
          {
            "Variable"     : "$.execution_registry.Item.status.S",
            "StringEquals" : "FP_CD",
            "Next"         : "WriteColdStorageFPDismissed"
          }
        ]
        Default = "FetchColdStorageProfile"
      }
      FetchColdStorageProfile = {
        Type     = "Task"
        Resource = "arn:aws:states:::aws-sdk:dynamodb:query"
        Parameters = {
          TableName              = aws_dynamodb_table.cold_storage.name
          KeyConditionExpression = "helmetId = :h"
          ExpressionAttributeValues = {
            ":h" = { "S.$" = "$.helmet_id" }
          }
          ScanIndexForward = false
          Limit            = 1
        }
        ResultPath = "$.cold_storage_profile"
        Next       = "CheckNOKEmailPresent"
      }
      CheckNOKEmailPresent = {
        Type = "Choice"
        Choices = [
          {
            "And" : [
              {
                "Variable" : "$.cold_storage_profile.Items[0]",
                "IsPresent" : true
              },
              {
                "Variable" : "$.cold_storage_profile.Items[0].next_of_kin_email",
                "IsPresent" : true
              },
              {
                "Variable" : "$.cold_storage_profile.Items[0].next_of_kin_email.S",
                "IsPresent" : true
              }
            ],
            "Next" : "SendSNSEmergencyAlert"
          }
        ]
        Default = "SendAdminMissingNOKAlert"
      }
      SendAdminMissingNOKAlert = {
        Type     = "Task"
        Resource = "arn:aws:states:::aws-sdk:ses:sendEmail"
        Parameters = {
          Destination = {
            ToAddresses = [
              var.sns-email-address
            ]
          }
          Message = {
            Subject = {
              "Data.$" = "States.Format('ALERT SYSTEM WARNING: Missing Next-of-Kin Email for Helmet {}', $.helmet_id)"
            }
            Body = {
              Text = {
                "Data.$" = "States.Format('SYSTEM WARNING: Crash confirmed for Helmet ID: {}. Timestamp: {}.\n\nHowever, NO Next-of-Kin email address was found in Cold Storage record. Please review rider profile registration immediately.', $.helmet_id, $.timestamp)"
              }
            }
          }
          Source = var.sns-email-address
        }
        ResultPath = null
        Next       = "WriteColdStorageConfirmed"
      }
      SendSNSEmergencyAlert = {
        Type     = "Task"
        Resource = "arn:aws:states:::aws-sdk:ses:sendEmail"
        Parameters = {
          Destination = {
            "ToAddresses.$" = "States.Array($.cold_storage_profile.Items[0].next_of_kin_email.S)"
          }
          Message = {
            Subject = {
              "Data.$" = "States.Format('CRITICAL EMERGENCY ALERT: Helmet {} Crash Confirmed', $.helmet_id)"
            }
            Body = {
              Text = {
                "Data.$" = "States.Format('EMERGENCY INCIDENT CONFIRMED!\n\nHelmet ID: {}\nTimestamp: {}\n\nImmediate emergency assistance dispatched.', $.helmet_id, $.timestamp)"
              }
            }
          }
          Source = var.sns-email-address
        }
        ResultPath = null
        Next       = "WriteColdStorageConfirmed"
      }
      WriteColdStorageCancelled = {
        Type     = "Task"
        Resource = "arn:aws:states:::dynamodb:putItem"
        Parameters = {
          TableName = aws_dynamodb_table.cold_storage.name
          Item = {
            "helmetId"  = { "S.$" = "$.helmet_id" }
            "timestamp" = { "N.$" = "States.Format('{}', $.timestamp)" }
            "Status"    = { "S" = "INCIDENT_CANCELLED" }
          }
        }
        ResultPath = null
        Next       = "DeleteExecutionRegistry"
      }
      WriteColdStorageFPDismissed = {
        Type     = "Task"
        Resource = "arn:aws:states:::dynamodb:putItem"
        Parameters = {
          TableName = aws_dynamodb_table.cold_storage.name
          Item = {
            "helmetId"  = { "S.$" = "$.helmet_id" }
            "timestamp" = { "N.$" = "States.Format('{}', $.timestamp)" }
            "Status"    = { "S" = "FALSE_POSITIVE_DISMISSED" }
          }
        }
        ResultPath = null
        Next       = "DeleteExecutionRegistry"
      }
      WriteColdStorageConfirmed = {
        Type     = "Task"
        Resource = "arn:aws:states:::dynamodb:putItem"
        Parameters = {
          TableName = aws_dynamodb_table.cold_storage.name
          Item = {
            "helmetId"  = { "S.$" = "$.helmet_id" }
            "timestamp" = { "N.$" = "States.Format('{}', $.timestamp)" }
            "Status"    = { "S" = "INCIDENT_CONFIRMED" }
          }
        }
        ResultPath = null
        Next       = "DeleteExecutionRegistry"
      }
      DeleteExecutionRegistry = {
        Type     = "Task"
        Resource = "arn:aws:states:::dynamodb:deleteItem"
        Parameters = {
          TableName = aws_dynamodb_table.execution_registry.name
          Key = {
            "helmetId" = { "S.$" = "$.helmet_id" }
          }
        }
        ResultPath = null
        End        = true
      }
      SilentExit = {
        Type = "Pass"
        End  = true
      }
    }
  })

  tags = {
    Name = "SmartHelmetAlertWorkflow"
  }
}

# 5. Reconciliation State Machine (SFN2)
resource "aws_sfn_state_machine" "reconciliation_state_machine" {
  name     = "SmartHelmetReconciliationWorkflow"
  role_arn = aws_iam_role.step_functions_role.arn

  definition = jsonencode({
    Comment = "State Machine for handling late alert reconciliation."
    StartAt = "DeleteExecutionRegistry"
    States = {
      DeleteExecutionRegistry = {
        Type     = "Task"
        Resource = "arn:aws:states:::dynamodb:deleteItem"
        Parameters = {
          TableName = aws_dynamodb_table.execution_registry.name
          Key = {
            "helmetId" = { "S.$" = "$.helmet_id" }
          }
        }
        ResultPath = null
        Next       = "QueryColdStorage"
      }
      QueryColdStorage = {
        Type     = "Task"
        Resource = "arn:aws:states:::aws-sdk:dynamodb:query"
        Parameters = {
          TableName              = aws_dynamodb_table.cold_storage.name
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
            "Next"          = "CheckNOKEmailPresentReconcile"
          }
        ]
        Default = "SilentExit"
      }
      CheckNOKEmailPresentReconcile = {
        Type = "Choice"
        Choices = [
          {
            "And" : [
              {
                "Variable" : "$.query_result.Items[0]",
                "IsPresent" : true
              },
              {
                "Variable" : "$.query_result.Items[0].next_of_kin_email",
                "IsPresent" : true
              },
              {
                "Variable" : "$.query_result.Items[0].next_of_kin_email.S",
                "IsPresent" : true
              }
            ],
            "Next" : "SendSNSStandDown"
          }
        ]
        Default = "SendAdminMissingNOKStandDown"
      }
      SendAdminMissingNOKStandDown = {
        Type     = "Task"
        Resource = "arn:aws:states:::aws-sdk:ses:sendEmail"
        Parameters = {
          Destination = {
            ToAddresses = [
              var.sns-email-address
            ]
          }
          Message = {
            Subject = {
              "Data.$" = "States.Format('EMERGENCY STAND-DOWN WARNING: Missing Next-of-Kin Email for Helmet {}', $.helmet_id)"
            }
            Body = {
              Text = {
                "Data.$" = "States.Format('SYSTEM WARNING: Emergency stand-down initiated for Helmet ID: {}.\n\nHowever, Next-of-Kin email address was missing in Cold Storage. Admin notified.', $.helmet_id)"
              }
            }
          }
          Source = var.sns-email-address
        }
        ResultPath = null
        Next       = "UpdateColdStorageCancelled"
      }
      SendSNSStandDown = {
        Type     = "Task"
        Resource = "arn:aws:states:::aws-sdk:ses:sendEmail"
        Parameters = {
          Destination = {
            "ToAddresses.$" = "States.Array($.query_result.Items[0].next_of_kin_email.S)"
          }
          Message = {
            Subject = {
              "Data.$" = "States.Format('EMERGENCY STAND-DOWN: Helmet {} Alert Resolved', $.helmet_id)"
            }
            Body = {
              Text = {
                "Data.$" = "States.Format('EMERGENCY STAND-DOWN!\n\nHelmet ID: {}\nStatus: RESOLVED_BY_LATE_CANCEL\n\nThe rider cancelled the alert within the safe window.', $.helmet_id)"
              }
            }
          }
          Source = var.sns-email-address
        }
        ResultPath = null
        Next       = "UpdateColdStorageCancelled"
      }
      UpdateColdStorageCancelled = {
        Type     = "Task"
        Resource = "arn:aws:states:::dynamodb:putItem"
        Parameters = {
          TableName = aws_dynamodb_table.cold_storage.name
          Item = {
            "helmetId"  = { "S.$" = "$.helmet_id" }
            "timestamp" = { "N.$" = "States.Format('{}', $.timestamp)" }
            "Status"    = { "S" = "RESOLVED_BY_LATE_CANCEL" }
          }
        }
        ResultPath = null
        End        = true
      }
      SilentExit = {
        Type = "Pass"
        End  = true
      }
    }
  })

  tags = {
    Name = "SmartHelmetReconciliationWorkflow"
  }
}
