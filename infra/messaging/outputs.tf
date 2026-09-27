output "telemetry_queue_url" {
  value = aws_sqs_queue.telemetry_queue.url
}
output "telemetry_queue_arn" {
  value = aws_sqs_queue.telemetry_queue.arn
}
output "telemetry_queue_name" {
  value = aws_sqs_queue.telemetry_queue.name
}

output "control_queue_url" {
  value = aws_sqs_queue.control_queue.url
}
output "control_queue_arn" {
  value = aws_sqs_queue.control_queue.arn
}
output "control_queue_name" {
  value = aws_sqs_queue.control_queue.name
}

output "lwt_queue_url" {
  value = aws_sqs_queue.lwt_queue.url
}
output "lwt_queue_arn" {
  value = aws_sqs_queue.lwt_queue.arn
}
output "lwt_queue_name" {
  value = aws_sqs_queue.lwt_queue.name
}

output "crash_queue_url" {
  value = aws_sqs_queue.crash_queue.url
}
output "crash_queue_arn" {
  value = aws_sqs_queue.crash_queue.arn
}
output "crash_queue_name" {
  value = aws_sqs_queue.crash_queue.name
}

output "alert_queue_url" {
  value = aws_sqs_queue.alert_queue.url
}
output "alert_queue_arn" {
  value = aws_sqs_queue.alert_queue.arn
}
output "alert_queue_name" {
  value = aws_sqs_queue.alert_queue.name
}

output "override_queue_url" {
  value = aws_sqs_queue.override_queue.url
}
output "override_queue_arn" {
  value = aws_sqs_queue.override_queue.arn
}
output "override_queue_name" {
  value = aws_sqs_queue.override_queue.name
}
