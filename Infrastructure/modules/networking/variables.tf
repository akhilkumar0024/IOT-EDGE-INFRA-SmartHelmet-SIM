variable "vpc-cidr" {
  description = "CIDR Block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public-subnets-CIDR-AZ" {
  description = "CIDR blocks and AZ for the publuc subnets"
  type = map(object({
    az   = string
    cidr = string
  }))
  default = {
    subnet1 = {
      az   = "ap-south-1a"
      cidr = "10.0.1.0/24"
    }
    subnet2 = {
      az   = "ap-south-1b"
      cidr = "10.0.2.0/24"
    }
  }
}
