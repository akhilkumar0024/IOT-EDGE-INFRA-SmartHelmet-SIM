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
