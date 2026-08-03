# 1. Emergency Alerts SNS Topic
resource "aws_sns_topic" "smart-helmet-emergency-alerts" {
  name = "smart-helmet-emergency-alerts-topic"
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
        Default = "FetchColdStorageProfile"
      }
      FetchColdStorageProfile = {
        Type     = "Task"
        Resource = "arn:aws:states:::aws-sdk:dynamodb:query"
        Parameters = {
          TableName              = var.cold-storage-name
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
              var.sender_email
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
          Source = var.sender_email
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
          Source = var.sender_email
        }
        ResultPath = null
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
        ResultPath = null
        Next       = "DeleteExecutionRegistry"
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
        ResultPath = null
        Next       = "DeleteExecutionRegistry"
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
        ResultPath = null
        Next       = "DeleteExecutionRegistry"
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
        ResultPath = null
        End        = true
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
        ResultPath = null
        Next       = "QueryColdStorage"
      }
      QueryColdStorage = {
        Type     = "Task"
        Resource = "arn:aws:states:::aws-sdk:dynamodb:query"
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
              var.sender_email
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
          Source = var.sender_email
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
          Source = var.sender_email
        }
        ResultPath = null
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
        ResultPath = null
        End        = true
      }
      SilentExit = {
        Type = "Pass"
        End  = true
      }
    }
  })
}

