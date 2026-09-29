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

variable "hot-storage-name" {
  description = "Name for DynamoDB hot storage table"
  type        = string
  default     = "smart-helmet-hot-storage"
}

variable "cold-storage-name" {
  description = "Name for DynamoDB cold storage table"
  type        = string
  default     = "smart-helmet-cold-storage"
}

variable "execution-registry-name" {
  description = "Name for the execution registry DynamoDB table"
  type        = string
  default     = "smart-helmet-execution-registry"
}

variable "device-status-db-table-name" {
  description = "Name for the device status database table"
  type        = string
  default     = "smart-helmet-device-status"
}

variable "sns-email-address" {
  description = "Email Address to send emergency alerts and notifications"
  type        = string
  default     = "akhilkumar0024.devops@gmail.com"
}
