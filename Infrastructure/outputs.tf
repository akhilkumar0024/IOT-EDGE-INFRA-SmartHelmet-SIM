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

output "aws-sg-ecs-infra-id" {
  description = "ID of the Security Group for the ECS Infra"
  value       = module.ecs-security-group.aws-sg-ecs-infra-id
}

output "aws-sg-ecs-infra-name" {
  description = "Name of the Security Group for the ECS Infra"
  value       = module.ecs-security-group.aws-sg-ecs-infra-name
}
