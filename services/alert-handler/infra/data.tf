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
data "aws_ssm_parameter" "alert_queue_url" {
  name = "/smart-helmet/queues/alert-queue-url"
}

data "aws_ssm_parameter" "alert_queue_arn" {
  name = "/smart-helmet/queues/alert-queue-arn"
}

data "aws_ssm_parameter" "alert_queue_name" {
  name = "/smart-helmet/queues/alert-queue-name"
}

data "aws_ssm_parameter" "override_queue_url" {
  name = "/smart-helmet/queues/override-queue-url"
}

data "aws_ssm_parameter" "override_queue_arn" {
  name = "/smart-helmet/queues/override-queue-arn"
}

data "aws_ssm_parameter" "override_queue_name" {
  name = "/smart-helmet/queues/override-queue-name"
}

# Fetch Shared Data Parameters
data "aws_ssm_parameter" "execution_registry_name" {
  name = "/smart-helmet/data/execution-registry-name"
}

data "aws_ssm_parameter" "execution_registry_arn" {
  name = "/smart-helmet/data/execution-registry-arn"
}

data "aws_ssm_parameter" "alert_state_machine_arn" {
  name = "/smart-helmet/data/alert-state-machine-arn"
}

data "aws_ssm_parameter" "reconciliation_state_machine_arn" {
  name = "/smart-helmet/data/reconciliation-state-machine-arn"
}
