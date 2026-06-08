#1.Create VPC for the ECS Fargate
resource "aws_vpc" "main" {
  cidr_block           = var.vpc-cidr
  instance_tenancy     = "default"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "smarthelmet-vpc"
  }
}
#2 Create Internet Gateway for the VPC
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "smarthelmet-igw"
  }
}

#3 Create Public Subnets
resource "aws_subnet" "main" {
  for_each                = var.public-subnets
  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = true # automatically assigns public ip to the instances launched in the subnet

  tags = {
    Name = "Public-${each.key}-${each.value.az}"
  }
}

#4 Create a Route Table for the public subnets

