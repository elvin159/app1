# Terraform root for one stack. Identical in every environment and region: the environment and region
# come from the folder names, everything else from ../../env.yaml.
terraform {
  required_version = "1.17.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.70.0"
    }
  }

  # CI passes the bucket (state_bucket in env.yaml) and the key (this folder's path).
  backend "s3" {
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

locals {
  environment = basename(abspath("${path.module}/../.."))
  region      = basename(abspath("${path.module}/.."))
  config      = yamldecode(file("${path.module}/../../env.yaml"))
}

# OIDC only: CI assumes a role in this account. allowed_account_ids stops a run against the wrong account.
provider "aws" {
  region              = local.region
  allowed_account_ids = [local.config.account_id]

  default_tags {
    tags = {
      Application = "app1"
      Environment = local.environment
      ManagedBy   = "terraform"
    }
  }
}

module "compute" {
  source = "../../../stacks/compute"

  region = local.region
  config = local.config
}

output "compute" {
  description = "Outputs of stacks/compute."
  value       = module.compute
}
