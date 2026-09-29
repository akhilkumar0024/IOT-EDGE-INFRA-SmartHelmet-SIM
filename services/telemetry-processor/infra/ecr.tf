resource "aws_ecr_repository" "telemetry_repo" {
  name                 = "smart-helmet-telemetry-service-repo"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "smart-helmet-telemetry-service-repo"
  }
}
