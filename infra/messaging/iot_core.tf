resource "aws_iot_certificate" "simulator_certificate" {
  active = true
}

resource "aws_iot_policy" "simulator_policy" {
  name = "smart-helmet-simulator-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "iot:Connect"
        Resource = "arn:aws:iot:*:*:client/*"
      },
      {
        Effect = "Allow"
        Action = "iot:Publish"
        Resource = [
          "arn:aws:iot:*:*:topic/helmet/*/telemetry",
          "arn:aws:iot:*:*:topic/helmet/*/alert/override",
          "arn:aws:iot:*:*:topic/helmet/*/lwt",
          "arn:aws:iot:*:*:topic/helmet/*/control"
        ]
      },
      {
        Effect   = "Allow"
        Action   = "iot:Subscribe"
        Resource = "arn:aws:iot:*:*:topicfilter/helmet/*/alert/status"
      },
      {
        Effect   = "Allow"
        Action   = "iot:Receive"
        Resource = "arn:aws:iot:*:*:topic/helmet/*/alert/status"
      }
    ]
  })
}

resource "aws_iot_policy_attachment" "simulator_policy_attachment" {
  policy = aws_iot_policy.simulator_policy.name
  target = aws_iot_certificate.simulator_certificate.arn
}

resource "aws_ssm_parameter" "iot_private_key" {
  name        = "/smart-helmet/simulator/private_key"
  description = "Private key for the IoT Simulator"
  type        = "SecureString"
  value       = aws_iot_certificate.simulator_certificate.private_key
}

resource "aws_ssm_parameter" "iot_certificate_pem" {
  name        = "/smart-helmet/simulator/certificate_pem"
  description = "Certificate PEM for the IoT Simulator"
  type        = "SecureString"
  value       = aws_iot_certificate.simulator_certificate.certificate_pem
}

resource "aws_iam_role" "iot_sqs_role" {
  name = "smart-helmet-iot-sqs-access-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "iot.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "smart-helmet-iot-sqs-access-role"
  }
}

resource "aws_iam_policy" "iot_sqs_policy" {
  name = "smart-helmet-iot-sqs-access-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sqs:SendMessage"
        Effect = "Allow"
        Resource = [
          aws_sqs_queue.telemetry_queue.arn,
          aws_sqs_queue.override_queue.arn,
          aws_sqs_queue.lwt_queue.arn,
          aws_sqs_queue.control_queue.arn
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "iot_sqs_attach" {
  role       = aws_iam_role.iot_sqs_role.name
  policy_arn = aws_iam_policy.iot_sqs_policy.arn
}

resource "aws_iot_topic_rule" "telemetry_rule" {
  name        = "iot_telemetry_data_rule"
  description = "Routes telemetry data to Telemetry Queue"
  enabled     = true
  sql         = "SELECT * FROM 'helmet/+/telemetry'"
  sql_version = "2016-03-23"

  sqs {
    queue_url  = aws_sqs_queue.telemetry_queue.url
    role_arn   = aws_iam_role.iot_sqs_role.arn
    use_base64 = false
  }
}

resource "aws_iot_topic_rule" "override_rule" {
  name        = "iot_override_alert_rule"
  description = "Routes override MQTT messages to Override Queue"
  enabled     = true
  sql         = "SELECT * FROM 'helmet/+/alert/override'"
  sql_version = "2016-03-23"

  sqs {
    queue_url  = aws_sqs_queue.override_queue.url
    role_arn   = aws_iam_role.iot_sqs_role.arn
    use_base64 = false
  }
}

resource "aws_iot_topic_rule" "lwt_rule" {
  name        = "iot_lwt_rule"
  description = "Routes LWT MQTT messages to LWT Queue"
  enabled     = true
  sql         = "SELECT * FROM 'helmet/+/lwt'"
  sql_version = "2016-03-23"

  sqs {
    queue_url  = aws_sqs_queue.lwt_queue.url
    role_arn   = aws_iam_role.iot_sqs_role.arn
    use_base64 = false
  }
}

resource "aws_iot_topic_rule" "control_rule" {
  name        = "iot_control_rule"
  description = "Routes control MQTT messages to Control Queue"
  enabled     = true
  sql         = "SELECT * FROM 'helmet/+/control'"
  sql_version = "2016-03-23"

  sqs {
    queue_url  = aws_sqs_queue.control_queue.url
    role_arn   = aws_iam_role.iot_sqs_role.arn
    use_base64 = false
  }
}
