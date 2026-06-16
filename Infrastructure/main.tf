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
  source                  = "./modules/database"
  hot-storage-name        = var.hot-storage-name
  cold-storage-name       = var.cold-storage-name
  execution-registry-name = var.execution-registry-name
}

module "messaging" {
  source = "./modules/messaging"

}

module "compute" {
  source                   = "./modules/compute"
  public-subnet-ids        = module.networking.public-subnet-ids
  telemetry-queue-arn      = module.messaging.telemetry-queue-arn
  control-queue-arn        = module.messaging.control-queue-arn
  crash-queue-arn          = module.messaging.crash-queue-arn
  alert-queue-arn          = module.messaging.alert-queue-arn
  LWT-queue-arn            = module.messaging.lwt-queue-arn
  override-queue-arn       = module.messaging.override-queue-arn
  telemetry-queue-url      = module.messaging.telemetry-queue-url
  control-queue-url        = module.messaging.control-queue-url
  crash-queue-url          = module.messaging.crash-queue-url
  alert-queue-url          = module.messaging.alert-queue-url
  LWT-queue-url            = module.messaging.lwt-queue-url
  override-queue-url       = module.messaging.override-queue-url
  hot-storage-arn          = module.database.hot-storage-arn
  cold-storage-arn         = module.database.cold-storage-arn
  execution-registry-arn   = module.database.execution-registry-arn
  hot-storage-name         = module.database.hot-storage-name
  cold-storage-name        = module.database.cold-storage-name
  execution-registry-name  = module.database.execution-registry-name
  telemetry-code-repo-url  = module.ecr.telemetry-code-repo-url
  processing-code-repo-url = module.ecr.processing-code-repo-url
  alert-code-repo-url      = module.ecr.alert-code-repo-url
  ecs-security-group-id    = module.ecs-security-group.aws-sg-ecs-infra-id
}

module "ecr" {
  source = "./modules/ecr"

  telemetry-code-repo-name  = var.ecr-repo-names["telemetry-code-repo-name"]
  processing-code-repo-name = var.ecr-repo-names["processing-code-repo-name"]
  alert-code-repo-name      = var.ecr-repo-names["alert-code-repo-name"]
}
