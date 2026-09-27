# Fetch Platform Parameters
data "aws_ssm_parameter" "ecs_cluster_name" {
  name = "/smart-helmet/platform/ecs-cluster-name"
}

data "aws_ssm_parameter" "ecs_cluster_arn" {
  name = "/smart-helmet/platform/ecs-cluster-arn"
}

data "aws_ssm_parameter" "ecs_security_group_id" {
  name = "/smart-helmet/platform/ecs-security-group-id"
}

data "aws_ssm_parameter" "ecs_execution_role_arn" {
  name = "/smart-helmet/platform/ecs-execution-role-arn"
}

data "aws_ssm_parameter" "ecs_log_group_name" {
  name = "/smart-helmet/platform/ecs-log-group-name"
}

data "aws_ssm_parameter" "public_subnet_ids" {
  name = "/smart-helmet/platform/public-subnet-ids"
}

# Fetch Messaging Parameters
data "aws_ssm_parameter" "control_queue_url" {
  name = "/smart-helmet/queues/control-queue-url"
}

data "aws_ssm_parameter" "control_queue_arn" {
  name = "/smart-helmet/queues/control-queue-arn"
}

data "aws_ssm_parameter" "control_queue_name" {
  name = "/smart-helmet/queues/control-queue-name"
}

data "aws_ssm_parameter" "crash_queue_url" {
  name = "/smart-helmet/queues/crash-queue-url"
}

data "aws_ssm_parameter" "crash_queue_arn" {
  name = "/smart-helmet/queues/crash-queue-arn"
}

data "aws_ssm_parameter" "crash_queue_name" {
  name = "/smart-helmet/queues/crash-queue-name"
}

data "aws_ssm_parameter" "lwt_queue_url" {
  name = "/smart-helmet/queues/lwt-queue-url"
}

data "aws_ssm_parameter" "lwt_queue_arn" {
  name = "/smart-helmet/queues/lwt-queue-arn"
}

data "aws_ssm_parameter" "lwt_queue_name" {
  name = "/smart-helmet/queues/lwt-queue-name"
}

data "aws_ssm_parameter" "alert_queue_url" {
  name = "/smart-helmet/queues/alert-queue-url"
}

data "aws_ssm_parameter" "alert_queue_arn" {
  name = "/smart-helmet/queues/alert-queue-arn"
}

# Fetch Shared Data Parameters
data "aws_ssm_parameter" "hot_storage_name" {
  name = "/smart-helmet/data/hot-storage-name"
}

data "aws_ssm_parameter" "hot_storage_arn" {
  name = "/smart-helmet/data/hot-storage-arn"
}

data "aws_ssm_parameter" "cold_storage_name" {
  name = "/smart-helmet/data/cold-storage-name"
}

data "aws_ssm_parameter" "cold_storage_arn" {
  name = "/smart-helmet/data/cold-storage-arn"
}

data "aws_ssm_parameter" "device_status_table_name" {
  name = "/smart-helmet/data/device-status-table-name"
}

data "aws_ssm_parameter" "device_status_table_arn" {
  name = "/smart-helmet/data/device-status-table-arn"
}
