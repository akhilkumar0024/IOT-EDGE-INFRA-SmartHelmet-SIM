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

output "hot-storage-id" {
  description = "Id of the Hot Storage"
  value       = module.database.hot-storage-id
}

output "hot-storage-name" {
  description = "Name of the Hot Storage Db"
  value       = module.database.hot-storage-name
}


output "hot-storage-arn" {
  description = "arn of the Hot Storage Db"
  value       = module.database.hot-storage-arn
}


output "cold-storage-id" {
  description = "Id of the Cold Storage"
  value       = module.database.cold-storage-id
}

output "cold-storage-name" {
  description = "Name of Cold Storage"
  value       = module.database.cold-storage-name
}

output "cold-storage-arn" {
  description = "arn of the Cold Storage Db"
  value       = module.database.cold-storage-arn
}

output "execution-registry-id" {
  description = "Id of the Execution Registry"
  value       = module.database.execution-registry-id
}

output "execution-registry-name" {
  description = "Name of the Execution Registry Db"
  value       = module.database.execution-registry-name
}

output "execution-registry-arn" {
  description = "arn of the Execution Registry Db"
  value       = module.database.execution-registry-arn
}

