locals {
  this = var.config.regions[var.region]
}

module "networking" {
  source = "git::https://github.com/elvin159/terraform-aws-networking.git?ref=b929e585ecde926a9164b161091dc9abb465f278"

  # The VPC's Name tag; later stacks look the VPC up by it.
  name                    = local.this.cluster_name
  vpc_cidr                = local.this.vpc_cidr
  az_count                = local.this.az_count
  single_nat_gateway      = var.config.networking.single_nat_gateway
  flow_log_retention_days = var.config.log_retention_days
}
