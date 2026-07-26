variable "github_repo" {
  description = "GitHub repository in format owner/repo"
  type        = string
  default     = "akhilkumar0024/IOT-EDGE-INFRA-SmartHelmet-SIM"
}

variable "deploy_role_name" {
  description = "Name for the IAM Role assumed by Application Deployment pipeline"
  type        = string
  default     = "GitHubActionsAppDeployRole"
}

variable "terraform_role_name" {
  description = "Name for the IAM Role assumed by Terraform PR Checks pipeline"
  type        = string
  default     = "GitHubActionsInfraCheckRole"
}
