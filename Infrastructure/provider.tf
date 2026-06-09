terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.49.0"
    }
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      project_name = var.project-name
      environment  = var.environment
    }
  }
}
