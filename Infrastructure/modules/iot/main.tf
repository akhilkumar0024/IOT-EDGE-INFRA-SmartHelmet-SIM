#1.Certificate for the devices 
resource "aws_iot_certificate" "helmet-simulator-certificate" {
  active = true
}

#2.IOT Policy 
resource "aws_iot_policy" "helmet-simulator-policy" {
  name = "smart-helmet-simulator-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        #Allow python script to connect using any client ID
        Effect   = "Allow"
        Action   = "iot:Connect"
        Resource = "arn:aws:iot:*:*:client/*"
      },
      {
        #Allow to publish only to topics of telemetry Queue, overrride Queue and LWT Queue
        Effect = "Allow"
        Action = "iot:Publish",
        Resource = [
          "arn:aws:iot:*:*:topic/helmet/*/telemetry",
          "arn:aws:iot:*:*:topic/helmet/*/alert/override",
          "arn:aws:iot:*:*:topic/helmet/*/lwt"
        ]
      },
      {
        # Allow subscribing ONLY to the alert status topic
        Effect   = "Allow"
        Action   = "iot:Subscribe"
        Resource = "arn:aws:iot:*:*:topicfilter/helmet/*/alert/status"
      },
      {
        # Allow receiving messages ONLY from the alert status topic
        Effect   = "Allow"
        Action   = "iot:Receive"
        Resource = "arn:aws:iot:*:*:topic/helmet/*/alert/status"
      }
    ]
  })
}

#3.Attach Policy to certificate 
resource "aws_iot_policy_attachment" "helmet-simulator-policy-attachment" {
  policy = aws_iot_policy.helmet-simulator-policy.name
  target = aws_iot_certificate.helmet-simulator-certificate.arn
}

#4.Save Keys securely to AWS SSM for CI/CD compatibility
resource "aws_ssm_parameter" "iot_private_key" {
  name        = "/smart-helmet/simulator/private_key"
  description = "Private key for the IoT Simulator"
  type        = "SecureString"
  value       = aws_iot_certificate.helmet-simulator-certificate.private_key
}

resource "aws_ssm_parameter" "iot_certificate_pem" {
  name        = "/smart-helmet/simulator/certificate_pem"
  description = "Certificate PEM for the IoT Simulator"
  type        = "SecureString"
  value       = aws_iot_certificate.helmet-simulator-certificate.certificate_pem
}

#5. IAM Role to allow IOT to forward messages to SQS Queues
resource "aws_iam_role" "iot-sqs-access-role" {
  name = "iot-sqs-access-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "iot.amazonaws.com"
        }
      },
    ]
  })
}

#6. IAM Policy for the iot-sqs-role
resource "aws_iam_policy" "iot-sqs-access-policy" {
  name = "iot-sqs-access-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sqs:SendMessage"
        Effect = "Allow"
        Resource = [
          var.telemetry-queue-arn,
          var.override-queue-arn,
          var.LWT-queue-arn,
        ]
      }
    ]
  })
}

#7. Attach Policy to role
resource "aws_iam_role_policy_attachment" "iot-sqs-role-policy-attachment" {
  role       = aws_iam_role.iot-sqs-access-role.name
  policy_arn = aws_iam_policy.iot-sqs-access-policy.arn
}

#8.IOT Topic Rules
#Rule 1 : 
resource "aws_iot_topic_rule" "iot-telemetry-data-rule" {
  name        = "iot_telemetry_data_rule"
  description = "Routes telemetry data to the Telemetry Queue"
  enabled     = true
  sql         = "SELECT * FROM 'helmet/+/telemetry'"
  sql_version = "2016-03-23"

  sqs {
    queue_url  = var.telemetry-queue-url
    role_arn   = aws_iam_role.iot-sqs-access-role.arn
    use_base64 = false
  }
}

#Rule 2 : 
resource "aws_iot_topic_rule" "iot-override-alert-rule" {
  name        = "iot_override_alert_rule"
  description = "Routes override MQTT messages to the Override Queue"
  enabled     = true
  sql         = "SELECT * FROM 'helmet/+/alert/override'"
  sql_version = "2016-03-23"

  sqs {
    queue_url  = var.override-queue-url
    role_arn   = aws_iam_role.iot-sqs-access-role.arn
    use_base64 = false
  }
}

#Rule 3 :
resource "aws_iot_topic_rule" "iot-lwt-rule" {
  name        = "iot_lwt_rule"
  description = "Routes LWT MQTT messages to the LWT Queue"
  enabled     = true
  sql         = "SELECT * FROM 'helmet/+/lwt'"
  sql_version = "2016-03-23"

  sqs {
    queue_url  = var.LWT-queue-url
    role_arn   = aws_iam_role.iot-sqs-access-role.arn
    use_base64 = false
  }
}
