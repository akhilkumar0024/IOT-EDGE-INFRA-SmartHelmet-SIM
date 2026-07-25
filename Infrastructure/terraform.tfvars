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


hot-storage-name        = "hot-storage"
cold-storage-name       = "cold-storage"
execution-registry-name = "execution-registry"


ecr-repo-names = {
  "telemetry-code-repo-name"  = "telemetry-service-repo"
  "processing-code-repo-name" = "processing-service-repo"
  "alert-code-repo-name"      = "alert-service-repo"
}

sns-email-address = "akhilkumar0024.devops@gmail.com"


