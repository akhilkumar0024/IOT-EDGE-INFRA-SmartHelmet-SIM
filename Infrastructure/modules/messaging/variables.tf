variable "telemetry_queue_name" {
  type    = string
  default = "smart-helmet-telemetry-queue"
}
variable "telemetry_dlq_name" {
  type    = string
  default = "smart-helmet-telemetry-dlq"
}

variable "control_queue_name" {
  type    = string
  default = "smart-helmet-control-queue"
}
variable "control_dlq_name" {
  type    = string
  default = "smart-helmet-control-dlq"
}

variable "lwt_queue_name" {
  type    = string
  default = "smart-helmet-LWT-queue"
}
variable "lwt_dlq_name" {
  type    = string
  default = "smart-helmet-LWT-dlq"
}

variable "crash_queue_name" {
  type    = string
  default = "smart-helmet-crash-queue"
}
variable "crash_dlq_name" {
  type    = string
  default = "smart-helmet-crash-dlq"
}

variable "alert_queue_name" {
  type    = string
  default = "smart-helmet-alert-queue"
}
variable "alert_dlq_name" {
  type    = string
  default = "smart-helmet-alert-dlq"
}

variable "override_queue_name" {
  type    = string
  default = "smart-helmet-override-queue"
}
variable "override_dlq_name" {
  type    = string
  default = "smart-helmet-override-dlq"
}
