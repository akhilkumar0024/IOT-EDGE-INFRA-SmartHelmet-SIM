output "deploy_role_arn" {
  description = "ARN of the IAM Role for Application Deployment pipeline"
  value       = aws_iam_role.github_actions_deploy.arn
}

output "terraform_role_arn" {
  description = "ARN of the IAM Role for Terraform PR Checks pipeline"
  value       = aws_iam_role.github_actions_terraform.arn
}

output "provider_arn" {
  description = "ARN of the GitHub OIDC Provider"
  value       = aws_iam_openid_connect_provider.github.arn
}
