
output "telemetry-code-repo-url" {
  value = aws_ecr_repository.telemetry-repo.repository_url
}

output "processing-code-repo-url" {
  value = aws_ecr_repository.processing-code-repo.repository_url
}

output "alert-code-repo-url" {
  value = aws_ecr_repository.alert-code-repo.repository_url
}
