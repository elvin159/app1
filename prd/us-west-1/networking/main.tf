locals {
  environment  = "prd"
  account_id   = "333333333333"
  region       = "us-west-1"
  cluster_name = "app1-prd-usw1" # VPC Name tag; later stacks look the VPC up by it

  vpc_cidr           = "10.49.0.0/16" # unique across every environment and region
  az_count           = 2
  single_nat_gateway = false # true in dev only: one NAT gateway instead of one per AZ
  log_retention_days = 365
}

# OIDC only: CI assumes a role in this account. allowed_account_ids stops a run against the wrong account.
provider "aws" {
  region              = local.region
  allowed_account_ids = [local.account_id]

  default_tags {
    tags = {
      Application = "app1"
      Environment = local.environment
      ManagedBy   = "terraform"
    }
  }
}

module "networking" {
  source = "git::https://github.com/elvin159/terraform-aws-networking.git?ref=b929e585ecde926a9164b161091dc9abb465f278"

  name                    = local.cluster_name
  vpc_cidr                = local.vpc_cidr
  az_count                = local.az_count
  single_nat_gateway      = local.single_nat_gateway
  flow_log_retention_days = local.log_retention_days
}
