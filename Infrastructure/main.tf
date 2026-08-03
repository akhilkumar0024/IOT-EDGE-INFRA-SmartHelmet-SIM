module "networking" {
  source                 = "./modules/networking"
  vpc-cidr               = var.vpc-cidr
  public-subnets-CIDR-AZ = var.public-subnets-CIDR-AZ
}

module "ecs-security-group" {
  source = "./modules/security-groups"
  vpc-id = module.networking.vpc-id
}

module "database" {
  source                      = "./modules/database"
  hot-storage-name            = var.hot-storage-name
  cold-storage-name           = var.cold-storage-name
  execution-registry-name     = var.execution-registry-name
  device-status-db-table-name = var.device-status-db-table-name
}

module "messaging" {
  source = "./modules/messaging"

}

module "compute" {
  source                           = "./modules/compute"
  telemetry-queue-name             = module.messaging.telemetry-queue-name
  alert-queue-name                 = module.messaging.alert-queue-name
  override-queue-name              = module.messaging.override-queue-name
  LWT-queue-name                   = module.messaging.lwt-queue-name
  control-queue-name               = module.messaging.control-queue-name
  crash-queue-name                 = module.messaging.crash-queue-name
  public-subnet-ids                = module.networking.public-subnet-ids
  telemetry-queue-arn              = module.messaging.telemetry-queue-arn
  control-queue-arn                = module.messaging.control-queue-arn
  crash-queue-arn                  = module.messaging.crash-queue-arn
  alert-queue-arn                  = module.messaging.alert-queue-arn
  LWT-queue-arn                    = module.messaging.lwt-queue-arn
  override-queue-arn               = module.messaging.override-queue-arn
  telemetry-queue-url              = module.messaging.telemetry-queue-url
  control-queue-url                = module.messaging.control-queue-url
  crash-queue-url                  = module.messaging.crash-queue-url
  alert-queue-url                  = module.messaging.alert-queue-url
  LWT-queue-url                    = module.messaging.lwt-queue-url
  override-queue-url               = module.messaging.override-queue-url
  hot-storage-arn                  = module.database.hot-storage-arn
  cold-storage-arn                 = module.database.cold-storage-arn
  execution-registry-arn           = module.database.execution-registry-arn
  hot-storage-name                 = module.database.hot-storage-name
  cold-storage-name                = module.database.cold-storage-name
  execution-registry-name          = module.database.execution-registry-name
  telemetry-code-repo-url          = module.ecr.telemetry-code-repo-url
  processing-code-repo-url         = module.ecr.processing-code-repo-url
  alert-code-repo-url              = module.ecr.alert-code-repo-url
  ecs-security-group-id            = module.ecs-security-group.aws-sg-ecs-infra-id
  step_function_arn                = module.step-function.state_machine_arn
  reconciliation_step_function_arn = module.step-function.reconciliation_state_machine_arn
  ecs-log-group-name               = var.ecs-log-group-name
  device-status-db-table-name      = module.database.device-status-db-table-name
  device-status-db-table-arn       = module.database.device-status-db-table-arn
}

module "ecr" {
  source = "./modules/ecr"

  telemetry-code-repo-name  = var.ecr-repo-names["telemetry-code-repo-name"]
  processing-code-repo-name = var.ecr-repo-names["processing-code-repo-name"]
  alert-code-repo-name      = var.ecr-repo-names["alert-code-repo-name"]
}

module "parameter-store" {
  source = "./modules/parameter-store"
}

module "iot-core" {
  source              = "./modules/iot"
  override-queue-arn  = module.messaging.override-queue-arn
  override-queue-url  = module.messaging.override-queue-url
  telemetry-queue-arn = module.messaging.telemetry-queue-arn
  telemetry-queue-url = module.messaging.telemetry-queue-url
  LWT-queue-arn       = module.messaging.lwt-queue-arn
  LWT-queue-url       = module.messaging.lwt-queue-url
  control-queue-arn   = module.messaging.control-queue-arn
  control-queue-url   = module.messaging.control-queue-url
}

module "step-function" {
  source                  = "./modules/step-functions"
  cold-storage-arn        = module.database.cold-storage-arn
  execution-registry-arn  = module.database.execution-registry-arn
  execution-registry-name = module.database.execution-registry-name
  cold-storage-name       = var.cold-storage-name
  sender_email            = var.sns-email-address
}




module "monitoring" {
  source                           = "./modules/monitoring"
  step-function-arn                = module.step-function.state_machine_arn
  dynamodb-hot-storage-name        = var.hot-storage-name
  dynamoDB-cold-storage-name       = var.cold-storage-name
  dynamoDB-execution-registry-name = var.execution-registry-name
  sns-email-address                = var.sns-email-address
  telemetry-dlq-name               = module.messaging.telemetry-dlq-name
  control-dlq-name                 = module.messaging.control-dlq-name
  lwt-dlq-name                     = module.messaging.lwt-dlq-name
  crash-dlq-name                   = module.messaging.crash-dlq-name
  alert-dlq-name                   = module.messaging.alert-dlq-name
  override-dlq-name                = module.messaging.override-dlq-name

  queue_names = [
    module.messaging.telemetry-queue-name,
    module.messaging.control-queue-name,
    module.messaging.lwt-queue-name,
    module.messaging.crash-queue-name,
    module.messaging.alert-queue-name,
    module.messaging.override-queue-name
  ]

  ecs-log-group-name = var.ecs-log-group-name
}

module "oidc" {
  source           = "./modules/oidc"
  github_repo      = "akhilkumar0024/IOT-EDGE-INFRA-SmartHelmet-SIM"
  deploy_role_name = "smart-helmet-app-deploy-role"
  plan_role_name   = "smart-helmet-tf-plan-role"
  apply_role_name  = "smart-helmet-tf-deploy-role"
}


