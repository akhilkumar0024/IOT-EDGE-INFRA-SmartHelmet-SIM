region       = "ap-south-1"
project-name = "smart_helemet_infra"
environment  = "development"

vpc-cidr = "10.0.0.0/16"

public-subnets-CIDR-AZ = {
  "subnet1" = {
    az   = "ap-south-1a"
    cidr = "10.0.1.0/24"
  }
  "subnet2" = {
    az   = "ap-south-1b"
    cidr = "10.0.2.0/24"
  }
}

hot-storage-name        = "smart-helmet-hot-storage"
cold-storage-name       = "smart-helmet-cold-storage"
execution-registry-name = "smart-helmet-execution-registry"

ecr-repo-names = {
  "telemetry-code-repo-name"  = "smart-helmet-telemetry-service-repo"
  "processing-code-repo-name" = "smart-helmet-processing-service-repo"
  "alert-code-repo-name"      = "smart-helmet-alert-service-repo"
}

sns-email-address = "akhilkumar0024.devops@gmail.com"
