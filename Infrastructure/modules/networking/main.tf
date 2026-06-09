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
resource "aws_subnet" "public-subnets" {
  for_each                = var.public-subnets-CIDR-AZ
  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = true # automatically assigns public ip to the instances launched in the subnet

  tags = {
    Name = "Public-${each.key}-${each.value.az}"
  }
}

#4 Create a Route Table for the public subnets
resource "aws_route_table" "public-subnet-route-table" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "smarthelmet-public-route-table"
  }
}

#5 Associate PublicSubnets with the Route-Table
resource "aws_route_table_association" "public-subnet-route-table-association" {
  for_each       = aws_subnet.public-subnets
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public-subnet-route-table.id
}

#6 Create a VPC Endpoint for S3
resource "aws_vpc_endpoint" "s3-vpc-endpoint" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.ap-south-1.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.public-subnet-route-table.id]
  tags = {
    Name = "smart-helmet-s3-endpoint"
  }
}

#7 Create a VPC Endpoint for DynamoDB
resource "aws_vpc_endpoint" "dynamodb-vpc-endpoint" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.ap-south-1.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.public-subnet-route-table.id]
  tags = {
    Name = "smart-helmet-dynamodb-endpoint"
  }
}
