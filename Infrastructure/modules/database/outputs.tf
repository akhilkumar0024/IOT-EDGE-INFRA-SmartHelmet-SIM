output "hot-storage-id" {
  value = aws_dynamodb_table.smart-helmet-hot-storage.id
}

output "hot-storage-name" {
  value = aws_dynamodb_table.smart-helmet-hot-storage.name
}

output "hot-storage-arn" {
  value = aws_dynamodb_table.smart-helmet-hot-storage.arn
}

output "cold-storage-id" {
  value = aws_dynamodb_table.smart-helmet-cold-storage.id
}

output "cold-storage-name" {
  value = aws_dynamodb_table.smart-helmet-cold-storage.name
}

output "cold-storage-arn" {
  value = aws_dynamodb_table.smart-helmet-cold-storage.arn
}

output "execution-registry-id" {
  value = aws_dynamodb_table.smart-helmet-execution-registry.id
}

output "execution-registry-name" {
  value = aws_dynamodb_table.smart-helmet-execution-registry.name
}

output "execution-registry-arn" {
  value = aws_dynamodb_table.smart-helmet-execution-registry.arn
}
