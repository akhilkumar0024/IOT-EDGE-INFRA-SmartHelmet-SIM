variable "sns-email-address" {
  type        = string
  description = "Email Id To send infra alerts to"
}

variable "telemetry-dlq-name" {
  type        = string
  description = "telemetry dlq name"
}

variable "control-dlq-name" {
  type = string
}

variable "lwt-dlq-name" {
  type = string
}

variable "crash-dlq-name" {
  type = string
}

variable "alert-dlq-name" {
  type = string
}

variable "override-dlq-name" {
  type = string
}
