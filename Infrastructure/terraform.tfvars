region       = "ap-south-1"
project-name = "smart_helemet_infra"
environment  = "dev"

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

