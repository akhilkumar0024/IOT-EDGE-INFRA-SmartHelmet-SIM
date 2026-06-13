resource "aws_ecr_repository" "telemetry-repo" {
  name                 = var.telemetry-code-repo-name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "processing-code-repo" {
  name                 = var.processing-code-repo-name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "alert-code-repo" {
  name                 = var.alert-code-repo-name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}
