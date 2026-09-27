terraform {
  backend "s3" {
    bucket       = "smarthelmet-terraform-state"
    key          = "services/telemetry-processor/terraform.tfstate"
    region       = "ap-south-1"
    encrypt      = true
    use_lockfile = true
  }
}
