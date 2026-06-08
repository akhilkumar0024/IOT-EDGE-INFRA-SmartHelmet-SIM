variable "region" {
  type        = string
  description = "AWS Region"
  default     = "ap-south-1"
}

variable "environment" {
  type        = string
  description = "Environment"
  default     = "dev"
}

variable "project_name" {
  type        = string
  description = "Project Name"
  default     = "smart-helmet-infra"
}
