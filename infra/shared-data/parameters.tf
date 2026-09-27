# Business Logic Configuration Parameters in SSM Parameter Store

resource "aws_ssm_parameter" "false_positive_window" {
  name        = "/smart-helmet/config/false_positive_window_seconds"
  description = "False positive window in seconds"
  type        = "String"
  value       = "5"
}

resource "aws_ssm_parameter" "standard_alert_window" {
  name        = "/smart-helmet/config/standard_alert_window_seconds"
  description = "Standard alert countdown window in seconds"
  type        = "String"
  value       = "30"
}

resource "aws_ssm_parameter" "retrospective_alert_window" {
  name        = "/smart-helmet/config/retrospective_alert_window_seconds"
  description = "Retrospective alert window in seconds"
  type        = "String"
  value       = "300"
}

resource "aws_ssm_parameter" "unconfirmed_chunk_ttl" {
  name        = "/smart-helmet/config/unconfirmed_chunk_ttl_hours"
  description = "TTL for unconfirmed chunks in hours"
  type        = "String"
  value       = "25"
}

resource "aws_ssm_parameter" "mass_alert_threshold" {
  name        = "/smart-helmet/config/mass_alert_threshold"
  description = "Threshold count for mass alerts"
  type        = "String"
  value       = "100"
}

resource "aws_ssm_parameter" "firmware_anomaly_threshold" {
  name        = "/smart-helmet/config/firmware_anomaly_threshold"
  description = "Threshold count for firmware anomalies"
  type        = "String"
  value       = "50"
}

resource "aws_ssm_parameter" "lwt_grace_period" {
  name        = "/smart-helmet/config/lwt_grace_period_seconds"
  description = "LWT grace period in seconds"
  type        = "String"
  value       = "900"
}
