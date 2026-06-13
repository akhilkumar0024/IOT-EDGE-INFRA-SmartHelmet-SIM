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

variable "project-name" {
  type        = string
  description = "Project Name"
  default     = "smart-helmet-infra"
}

variable "vpc-cidr" {
  description = "CIDR Block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public-subnets-CIDR-AZ" {
  description = "CIDR blocks and AZ for the publuc subnets"
  type = map(object({
    az   = string
    cidr = string
  }))
  default = {
    subnet1 = {
      az   = "ap-south-1a"
      cidr = "10.0.1.0/24"
    }
    subnet2 = {
      az   = "ap-south-1b"
      cidr = "10.0.2.0/24"
    }
  }
}

variable "hot-storage-name" {
  description = "name for hot storage"
  type        = string
  default     = "smart-helmet-hot-storage"
}
variable "cold-storage-name" {
  description = "name for cold storage"
  type        = string
  default     = "smart-helmet-cold-storage"
}
variable "execution-registry-name" {
  description = "name for the execution registry"
  type        = string
  default     = "smart-helmet-execution-registry"
}

variable "ecr-repo-names" {
  description = "Name for ECR repos"
  type        = map(string)
  default = {
    "telemetry-code-repo-name"  = "telemetry-service-repo"
    "processing-code-repo-name" = "processing-service-repo"
    "alert-code-repo-name"      = "alert-service-repo"
  }
}
