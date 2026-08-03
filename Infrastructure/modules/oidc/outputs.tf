output "github_oidc_provider_arn" {
  description = "ARN of the GitHub OIDC Provider"
  value       = aws_iam_openid_connect_provider.github.arn
}

output "app_deploy_role_arn" {
  description = "ARN of the Application Deployment IAM Role"
  value       = aws_iam_role.github_actions_deploy.arn
}

output "tf_plan_role_arn" {
  description = "ARN of the Terraform PR Plan Check IAM Role"
  value       = aws_iam_role.github_actions_tf_plan.arn
}

output "tf_deploy_role_arn" {
  description = "ARN of the Terraform Main Apply IAM Role"
  value       = aws_iam_role.github_actions_tf_deploy.arn
}
