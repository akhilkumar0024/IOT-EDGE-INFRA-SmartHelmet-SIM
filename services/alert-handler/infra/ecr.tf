resource "aws_ecr_repository" "alert_repo" {
  name                 = "smart-helmet-alert-service-repo"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "smart-helmet-alert-service-repo"
  }
}
