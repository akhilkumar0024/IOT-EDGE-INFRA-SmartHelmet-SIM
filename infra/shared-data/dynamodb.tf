# 1. Hot Storage DynamoDB Table
resource "aws_dynamodb_table" "hot_storage" {
  name           = var.hot-storage-name
  billing_mode   = "PROVISIONED"
  hash_key       = "helmetId"
  range_key      = "timestamp"
  read_capacity  = 5
  write_capacity = 5

  attribute {
    name = "helmetId"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "N"
  }

  ttl {
    attribute_name = "TimeToExist"
    enabled        = true
  }

  tags = {
    Name = var.hot-storage-name
  }
}

# 2. Cold Storage DynamoDB Table
resource "aws_dynamodb_table" "cold_storage" {
  name           = var.cold-storage-name
  billing_mode   = "PROVISIONED"
  hash_key       = "helmetId"
  range_key      = "timestamp"
  read_capacity  = 5
  write_capacity = 5

  attribute {
    name = "helmetId"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "N"
  }

  tags = {
    Name = var.cold-storage-name
  }
}

# 3. Execution Registry DynamoDB Table
resource "aws_dynamodb_table" "execution_registry" {
  name           = var.execution-registry-name
  billing_mode   = "PROVISIONED"
  hash_key       = "helmetId"
  read_capacity  = 5
  write_capacity = 5

  attribute {
    name = "helmetId"
    type = "S"
  }

  ttl {
    attribute_name = "TimeToExist"
    enabled        = true
  }

  tags = {
    Name = var.execution-registry-name
  }
}

# 4. Device Status DynamoDB Table
resource "aws_dynamodb_table" "device_status" {
  name           = var.device-status-db-table-name
  billing_mode   = "PROVISIONED"
  hash_key       = "helmetId"
  read_capacity  = 3
  write_capacity = 3

  attribute {
    name = "helmetId"
    type = "S"
  }

  ttl {
    attribute_name = "TimeToExist"
    enabled        = true
  }

  tags = {
    Name = var.device-status-db-table-name
  }
}
