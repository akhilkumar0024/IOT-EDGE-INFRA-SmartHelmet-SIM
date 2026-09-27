variable "region" {
  type        = string
  description = "AWS Region"
  default     = "ap-south-1"
}

variable "environment" {
  type        = string
  description = "Environment name"
  default     = "dev"
}

variable "project-name" {
  type        = string
  description = "Project Name"
  default     = "smart_helmet_infra"
}

variable "telemetry_queue_name" {
  description = "Name for telemetry SQS queue"
  type        = string
  default     = "smart-helmet-telemetry-queue"
}

variable "telemetry_dlq_name" {
  description = "Name for telemetry DLQ"
  type        = string
  default     = "smart-helmet-telemetry-dlq"
}

variable "control_queue_name" {
  description = "Name for control SQS queue"
  type        = string
  default     = "smart-helmet-control-queue"
}

variable "control_dlq_name" {
  description = "Name for control DLQ"
  type        = string
  default     = "smart-helmet-control-dlq"
}

variable "lwt_queue_name" {
  description = "Name for LWT SQS queue"
  type        = string
  default     = "smart-helmet-LWT-queue"
}

variable "lwt_dlq_name" {
  description = "Name for LWT DLQ"
  type        = string
  default     = "smart-helmet-LWT-dlq"
}

variable "crash_queue_name" {
  description = "Name for crash SQS queue"
  type        = string
  default     = "smart-helmet-crash-queue"
}

variable "crash_dlq_name" {
  description = "Name for crash DLQ"
  type        = string
  default     = "smart-helmet-crash-dlq"
}

variable "alert_queue_name" {
  description = "Name for alert SQS queue"
  type        = string
  default     = "smart-helmet-alert-queue"
}

variable "alert_dlq_name" {
  description = "Name for alert DLQ"
  type        = string
  default     = "smart-helmet-alert-dlq"
}

variable "override_queue_name" {
  description = "Name for override SQS queue"
  type        = string
  default     = "smart-helmet-override-queue"
}

variable "override_dlq_name" {
  description = "Name for override DLQ"
  type        = string
  default     = "smart-helmet-override-dlq"
}
