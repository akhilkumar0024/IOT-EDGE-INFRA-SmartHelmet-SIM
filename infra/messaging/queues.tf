# 1. Telemetry Queue and DLQ
resource "aws_sqs_queue" "telemetry_queue" {
  name = var.telemetry_queue_name

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.telemetry_dlq.arn
    maxReceiveCount     = 3
  })

  tags = {
    Name = var.telemetry_queue_name
  }
}

resource "aws_sqs_queue" "telemetry_dlq" {
  name = var.telemetry_dlq_name

  tags = {
    Name = var.telemetry_dlq_name
  }
}

resource "aws_sqs_queue_redrive_allow_policy" "telemetry_dlq_redrive" {
  queue_url = aws_sqs_queue.telemetry_dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.telemetry_queue.arn]
  })
}

# 2. Control Queue and DLQ
resource "aws_sqs_queue" "control_queue" {
  name = var.control_queue_name

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.control_dlq.arn
    maxReceiveCount     = 3
  })

  tags = {
    Name = var.control_queue_name
  }
}

resource "aws_sqs_queue" "control_dlq" {
  name = var.control_dlq_name

  tags = {
    Name = var.control_dlq_name
  }
}

resource "aws_sqs_queue_redrive_allow_policy" "control_dlq_redrive" {
  queue_url = aws_sqs_queue.control_dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.control_queue.arn]
  })
}

# 3. LWT Queue and DLQ
resource "aws_sqs_queue" "lwt_queue" {
  name = var.lwt_queue_name

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.lwt_dlq.arn
    maxReceiveCount     = 3
  })

  tags = {
    Name = var.lwt_queue_name
  }
}

resource "aws_sqs_queue" "lwt_dlq" {
  name = var.lwt_dlq_name

  tags = {
    Name = var.lwt_dlq_name
  }
}

resource "aws_sqs_queue_redrive_allow_policy" "lwt_dlq_redrive" {
  queue_url = aws_sqs_queue.lwt_dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.lwt_queue.arn]
  })
}

# 4. Crash Queue and DLQ
resource "aws_sqs_queue" "crash_queue" {
  name = var.crash_queue_name

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.crash_dlq.arn
    maxReceiveCount     = 3
  })

  tags = {
    Name = var.crash_queue_name
  }
}

resource "aws_sqs_queue" "crash_dlq" {
  name = var.crash_dlq_name

  tags = {
    Name = var.crash_dlq_name
  }
}

resource "aws_sqs_queue_redrive_allow_policy" "crash_dlq_redrive" {
  queue_url = aws_sqs_queue.crash_dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.crash_queue.arn]
  })
}

# 5. Alert Queue and DLQ
resource "aws_sqs_queue" "alert_queue" {
  name = var.alert_queue_name

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.alert_dlq.arn
    maxReceiveCount     = 3
  })

  tags = {
    Name = var.alert_queue_name
  }
}

resource "aws_sqs_queue" "alert_dlq" {
  name = var.alert_dlq_name

  tags = {
    Name = var.alert_dlq_name
  }
}

resource "aws_sqs_queue_redrive_allow_policy" "alert_dlq_redrive" {
  queue_url = aws_sqs_queue.alert_dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.alert_queue.arn]
  })
}

# 6. Override Queue and DLQ
resource "aws_sqs_queue" "override_queue" {
  name = var.override_queue_name

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.override_dlq.arn
    maxReceiveCount     = 3
  })

  tags = {
    Name = var.override_queue_name
  }
}

resource "aws_sqs_queue" "override_dlq" {
  name = var.override_dlq_name

  tags = {
    Name = var.override_dlq_name
  }
}

resource "aws_sqs_queue_redrive_allow_policy" "override_dlq_redrive" {
  queue_url = aws_sqs_queue.override_dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.override_queue.arn]
  })
}
