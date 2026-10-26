# Terraform root for the account-level stack. Identical in every environment: the environment comes
# from the folder name, everything else from ../env.yaml.
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
  environment = basename(abspath("${path.module}/.."))
  config      = yamldecode(file("${path.module}/../env.yaml"))
  region      = local.config.primary_region # account-level resources live in the primary region
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

module "global" {
  source = "../../stacks/global"

  environment = local.environment
  config      = local.config
}

output "global" {
  description = "Outputs of stacks/global."
  value       = module.global
}
