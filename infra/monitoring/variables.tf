variable "region" {
  type        = string
  description = "AWS Region"
  default     = "ap-south-1"
}

variable "environment" {
  type        = string
  description = "Environment name"
  default     = "development"
}

variable "project-name" {
  type        = string
  description = "Project Name"
  default     = "smart_helmet_infra"
}

variable "sns-email-address" {
  description = "Email address for infra monitoring alerts. No default is committed: supply it via terraform.tfvars locally or the SNS_EMAIL_ADDRESS GitHub repository variable in CI."
  type        = string
}
