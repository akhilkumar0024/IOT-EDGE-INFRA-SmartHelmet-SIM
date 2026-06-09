output "vpc-id" {
  description = "The ID of the VPC"
  value       = module.networking.vpc-id
}

output "public-subnet-id" {
  description = "List of IDs of the public subnets"
  value       = module.networking.public-subnet-ids
}

output "public-subnet-name" {
  description = "List of names of the public subnets"
  value       = module.networking.public-subnet-names
}
