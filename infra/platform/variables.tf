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

variable "vpc-cidr" {
  description = "CIDR Block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public-subnets-CIDR-AZ" {
  description = "CIDR blocks and AZ for public subnets"
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

variable "ecs-cluster-name" {
  description = "Name of the ECS Fargate cluster"
  type        = string
  default     = "smart-helmet-cluster"
}

variable "ecs-log-group-name" {
  description = "CloudWatch Log Group name for ECS Cluster"
  type        = string
  default     = "/ecs/smart-helmet-cluster"
}

variable "github_repo" {
  description = "GitHub repository for OIDC federation"
  type        = string
  default     = "akhilkumar0024/IOT-EDGE-INFRA-SmartHelmet-SIM"
}

variable "deploy_role_name" {
  description = "IAM Role name for GitHub Actions app deployments"
  type        = string
  default     = "smart-helmet-app-deploy-role"
}

variable "plan_role_name" {
  description = "IAM Role name for GitHub Actions Terraform Plan"
  type        = string
  default     = "smart-helmet-tf-plan-role"
}

variable "apply_role_name" {
  description = "IAM Role name for GitHub Actions Terraform Apply"
  type        = string
  default     = "smart-helmet-tf-deploy-role"
}
