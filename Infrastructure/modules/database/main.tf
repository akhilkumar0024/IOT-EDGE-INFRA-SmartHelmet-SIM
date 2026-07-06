resource "aws_dynamodb_table" "smart-helmet-hot-storage" {
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

resource "aws_dynamodb_table" "smart-helmet-cold-storage" {
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

resource "aws_dynamodb_table" "smart-helmet-execution-registry" {
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

resource "aws_dynamodb_table" "smart-helmet-device-status" {
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
