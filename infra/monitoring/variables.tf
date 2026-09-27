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

variable "sns-email-address" {
  description = "Email Address to send infra monitoring alerts"
  type        = string
  default     = "akhilkumar0024.devops@gmail.com"
}
