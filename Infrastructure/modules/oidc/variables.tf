variable "github_repo" {
  description = "GitHub repository in format owner/repo"
  type        = string
  default     = "akhilkumar0024/IOT-EDGE-INFRA-SmartHelmet-SIM"
}

variable "deploy_role_name" {
  description = "Name for the IAM Role assumed by Application Deployment pipeline"
  type        = string
  default     = "smart-helmet-app-deploy-role"
}

variable "plan_role_name" {
  description = "Name for the IAM Role assumed by Terraform PR Checks pipeline (Dry-Run Plan)"
  type        = string
  default     = "smart-helmet-tf-plan-role"
}

variable "apply_role_name" {
  description = "Name for the IAM Role assumed by Terraform Main Branch pipeline (Live Apply)"
  type        = string
  default     = "smart-helmet-tf-deploy-role"
}
