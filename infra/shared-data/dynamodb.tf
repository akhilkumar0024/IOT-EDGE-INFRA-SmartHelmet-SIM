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

  # Continuous backup, 35-day restore window. On-demand backup storage is
  # billed per GB, so this is near-free at this table size and gives recovery
  # to any second in the last 35 days.
  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name = var.hot-storage-name
  }
}

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

  # Continuous backup, 35-day restore window. On-demand backup storage is
  # billed per GB, so this is near-free at this table size and gives recovery
  # to any second in the last 35 days.
  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name = var.cold-storage-name
  }
}

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

  # Continuous backup, 35-day restore window. On-demand backup storage is
  # billed per GB, so this is near-free at this table size and gives recovery
  # to any second in the last 35 days.
  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name = var.execution-registry-name
  }
}

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

  # Continuous backup, 35-day restore window. On-demand backup storage is
  # billed per GB, so this is near-free at this table size and gives recovery
  # to any second in the last 35 days.
  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name = var.device-status-db-table-name
  }
}
