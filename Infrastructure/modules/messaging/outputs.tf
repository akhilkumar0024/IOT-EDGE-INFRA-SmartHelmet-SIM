# Telemetry Queue Outputs
output "telemetry-queue-url" {
  value = aws_sqs_queue.smart-helmet-telemetry-queue.url
}
output "telemetry-queue-arn" {
  value = aws_sqs_queue.smart-helmet-telemetry-queue.arn
}
output "telemetry-dlq-url" {
  value = aws_sqs_queue.smart-helmet-telemetry-dlq.url
}
output "telemetry-dlq-arn" {
  value = aws_sqs_queue.smart-helmet-telemetry-dlq.arn
}

# Control Queue Outputs
output "control-queue-url" {
  value = aws_sqs_queue.smart-helmet-control-queue.url
}
output "control-queue-arn" {
  value = aws_sqs_queue.smart-helmet-control-queue.arn
}
output "control-dlq-url" {
  value = aws_sqs_queue.smart-helmet-control-dlq.url
}
output "control-dlq-arn" {
  value = aws_sqs_queue.smart-helmet-control-dlq.arn
}

# LWT Queue Outputs
output "lwt-queue-url" {
  value = aws_sqs_queue.smart-helmet-LWT-queue.url
}
output "lwt-queue-arn" {
  value = aws_sqs_queue.smart-helmet-LWT-queue.arn
}
output "lwt-dlq-url" {
  value = aws_sqs_queue.smart-helmet-LWT-dlq.url
}
output "lwt-dlq-arn" {
  value = aws_sqs_queue.smart-helmet-LWT-dlq.arn
}

# Crash Queue Outputs
output "crash-queue-url" {
  value = aws_sqs_queue.smart-helmet-crash-queue.url
}
output "crash-queue-arn" {
  value = aws_sqs_queue.smart-helmet-crash-queue.arn
}
output "crash-dlq-url" {
  value = aws_sqs_queue.smart-helmet-crash-dlq.url
}
output "crash-dlq-arn" {
  value = aws_sqs_queue.smart-helmet-crash-dlq.arn
}

# Alert Queue Outputs
output "alert-queue-url" {
  value = aws_sqs_queue.smart-helmet-alert-queue.url
}
output "alert-queue-arn" {
  value = aws_sqs_queue.smart-helmet-alert-queue.arn
}
output "alert-dlq-url" {
  value = aws_sqs_queue.smart-helmet-alert-dlq.url
}
output "alert-dlq-arn" {
  value = aws_sqs_queue.smart-helmet-alert-dlq.arn
}

# Override Queue Outputs
output "override-queue-url" {
  value = aws_sqs_queue.smart-helmet-override-queue.url
}
output "override-queue-arn" {
  value = aws_sqs_queue.smart-helmet-override-queue.arn
}
output "override-dlq-url" {
  value = aws_sqs_queue.smart-helmet-override-dlq.url
}
output "override-dlq-arn" {
  value = aws_sqs_queue.smart-helmet-override-dlq.arn
}
