module "networking" {
  source                 = "./modules/networking"
  vpc-cidr               = var.vpc-cidr
  public-subnets-CIDR-AZ = var.public-subnets-CIDR-AZ
}
