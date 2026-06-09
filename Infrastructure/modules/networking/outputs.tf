output "vpc-id" {
  description = "The ID of the VPC"
  value       = aws_vpc.main.id
}

output "public-subnet-ids" {
  description = "List of IDs of the public subnets"
  value       = [for subnet in aws_subnet.public-subnets : subnet.id]
}

output "public-subnet-names" {
  description = "List of Public Subnets"
  value       = [for subnet in aws_subnet.public-subnets : subnet.tags.Name]
}
