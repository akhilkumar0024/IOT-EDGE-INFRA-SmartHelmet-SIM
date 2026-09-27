# Fetch Infrastructure parameters dynamically from SSM Parameter Store

# From Platform Layer
data "aws_ssm_parameter" "ecs_cluster_name" {
  name = "/smart-helmet/platform/ecs-cluster-name"
}

data "aws_ssm_parameter" "ecs_log_group_name" {
  name = "/smart-helmet/platform/ecs-log-group-name"
}

# From Shared Data Layer
data "aws_ssm_parameter" "hot_storage_name" {
  name = "/smart-helmet/data/hot-storage-name"
}

data "aws_ssm_parameter" "cold_storage_name" {
  name = "/smart-helmet/data/cold-storage-name"
}

data "aws_ssm_parameter" "execution_registry_name" {
  name = "/smart-helmet/data/execution-registry-name"
}

data "aws_ssm_parameter" "alert_state_machine_arn" {
  name = "/smart-helmet/data/alert-state-machine-arn"
}

# From Messaging Layer (DLQ Names)
data "aws_ssm_parameter" "telemetry_dlq_name" {
  name = "/smart-helmet/queues/telemetry-dlq-name"
}

data "aws_ssm_parameter" "control_dlq_name" {
  name = "/smart-helmet/queues/control-dlq-name"
}

data "aws_ssm_parameter" "lwt_dlq_name" {
  name = "/smart-helmet/queues/lwt-dlq-name"
}

data "aws_ssm_parameter" "crash_dlq_name" {
  name = "/smart-helmet/queues/crash-dlq-name"
}

data "aws_ssm_parameter" "alert_dlq_name" {
  name = "/smart-helmet/queues/alert-dlq-name"
}

data "aws_ssm_parameter" "override_dlq_name" {
  name = "/smart-helmet/queues/override-dlq-name"
}

# From Messaging Layer (Queue Names for Old Message Age)
data "aws_ssm_parameter" "telemetry_queue_name" {
  name = "/smart-helmet/queues/telemetry-queue-name"
}

data "aws_ssm_parameter" "control_queue_name" {
  name = "/smart-helmet/queues/control-queue-name"
}

data "aws_ssm_parameter" "lwt_queue_name" {
  name = "/smart-helmet/queues/lwt-queue-name"
}

data "aws_ssm_parameter" "crash_queue_name" {
  name = "/smart-helmet/queues/crash-queue-name"
}

data "aws_ssm_parameter" "alert_queue_name" {
  name = "/smart-helmet/queues/alert-queue-name"
}

data "aws_ssm_parameter" "override_queue_name" {
  name = "/smart-helmet/queues/override-queue-name"
}
