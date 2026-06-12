#1.Telemetry Queue and DLQ
resource "aws_sqs_queue" "smart-helmet-telemetry-queue" {
  name = var.telemetry_queue_name

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.smart-helmet-telemetry-dlq.arn
    maxReceiveCount     = 3
  })
}

resource "aws_sqs_queue" "smart-helmet-telemetry-dlq" {
  name = var.telemetry_dlq_name
}

resource "aws_sqs_queue_redrive_allow_policy" "smart-helmet-telemetry-dlq-redrive-allow-policy" {
  queue_url = aws_sqs_queue.smart-helmet-telemetry-dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue",
    sourceQueueArns   = [aws_sqs_queue.smart-helmet-telemetry-queue.arn]
  })
}



#2.Control Queue and DLQ
resource "aws_sqs_queue" "smart-helmet-control-queue" {
  name = var.control_queue_name

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.smart-helmet-control-dlq.arn
    maxReceiveCount     = 3
  })
}

resource "aws_sqs_queue" "smart-helmet-control-dlq" {
  name = var.control_dlq_name
}

resource "aws_sqs_queue_redrive_allow_policy" "smart-helmet-control-dlq-redrive-allow-policy" {
  queue_url = aws_sqs_queue.smart-helmet-control-dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue",
    sourceQueueArns   = [aws_sqs_queue.smart-helmet-control-queue.arn]
  })
}



#3.LWT Queue and DLQ
resource "aws_sqs_queue" "smart-helmet-LWT-queue" {
  name = var.lwt_queue_name

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.smart-helmet-LWT-dlq.arn
    maxReceiveCount     = 3
  })
}

resource "aws_sqs_queue" "smart-helmet-LWT-dlq" {
  name = var.lwt_dlq_name
}

resource "aws_sqs_queue_redrive_allow_policy" "smart-helmet-LWT-dlq-redrive-allow-policy" {
  queue_url = aws_sqs_queue.smart-helmet-LWT-dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue",
    sourceQueueArns   = [aws_sqs_queue.smart-helmet-LWT-queue.arn]
  })
}



#4.Crash Queue and DLQ
resource "aws_sqs_queue" "smart-helmet-crash-queue" {
  name = var.crash_queue_name

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.smart-helmet-crash-dlq.arn
    maxReceiveCount     = 3
  })
}

resource "aws_sqs_queue" "smart-helmet-crash-dlq" {
  name = var.crash_dlq_name
}

resource "aws_sqs_queue_redrive_allow_policy" "smart-helmet-crash-dlq-redrive-allow-policy" {
  queue_url = aws_sqs_queue.smart-helmet-crash-dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue",
    sourceQueueArns   = [aws_sqs_queue.smart-helmet-crash-queue.arn]
  })
}



#5.Alert Queue and DLQ
resource "aws_sqs_queue" "smart-helmet-alert-queue" {
  name = var.alert_queue_name

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.smart-helmet-alert-dlq.arn
    maxReceiveCount     = 3
  })
}

resource "aws_sqs_queue" "smart-helmet-alert-dlq" {
  name = var.alert_dlq_name
}

resource "aws_sqs_queue_redrive_allow_policy" "smart-helmet-alert-dlq-redrive-allow-policy" {
  queue_url = aws_sqs_queue.smart-helmet-alert-dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue",
    sourceQueueArns   = [aws_sqs_queue.smart-helmet-alert-queue.arn]
  })
}


#6.Override Queue and DLQ
resource "aws_sqs_queue" "smart-helmet-override-queue" {
  name = var.override_queue_name

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.smart-helmet-override-dlq.arn
    maxReceiveCount     = 3
  })
}

resource "aws_sqs_queue" "smart-helmet-override-dlq" {
  name = var.override_dlq_name
}

resource "aws_sqs_queue_redrive_allow_policy" "smart-helmet-override-dlq-redrive-allow-policy" {
  queue_url = aws_sqs_queue.smart-helmet-override-dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue",
    sourceQueueArns   = [aws_sqs_queue.smart-helmet-override-queue.arn]
  })
}
