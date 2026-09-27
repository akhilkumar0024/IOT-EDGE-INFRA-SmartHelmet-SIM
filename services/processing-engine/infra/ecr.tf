resource "aws_ecr_repository" "processing_repo" {
  name                 = "smart-helmet-processing-service-repo"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "smart-helmet-processing-service-repo"
  }
}
