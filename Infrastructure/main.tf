module "networking" {
  source                 = "./modules/networking"
  vpc-cidr               = var.vpc-cidr
  public-subnets-CIDR-AZ = var.public-subnets-CIDR-AZ
}

module "ecs-security-group" {
  source = "./modules/security-groups"
  vpc-id = module.networking.vpc-id
}
