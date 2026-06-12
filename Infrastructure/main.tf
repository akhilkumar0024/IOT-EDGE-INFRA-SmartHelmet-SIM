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
  source = "./modules/compute"

  telemetry-queue-arn    = module.messaging.telemetry-queue-arn
  control-queue-arn      = module.messaging.control-queue-arn
  crash-queue-arn        = module.messaging.crash-queue-arn
  alert-queue-arn        = module.messaging.alert-queue-arn
  LWT-queue-arn          = module.messaging.lwt-queue-arn
  override-queue-arn     = module.messaging.override-queue-arn
  hot-storage-arn        = module.database.hot-storage-arn
  cold-storage-arn       = module.database.cold-storage-arn
  execution-registry-arn = module.database.execution-registry-arn
}
