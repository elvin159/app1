locals {
  environment          = "stg"
  account_id           = "222222222222"
  region               = "us-west-1"
  cluster_name         = "app1-stg-usw1"
  primary_region       = "us-east-1"
  primary_cluster_name = "app1-stg-use1"

  # Bootstrap prerequisites (stub values).
  hosted_zone_id       = "Z0000000000000000STG" # stg.example.com
  repo_ssh_secret_name = "app1/argocd-repo-ssh-key"
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

# EKS cluster from the compute stack.
data "aws_eks_cluster" "this" {
  name = local.cluster_name
}

data "aws_iam_openid_connect_provider" "this" {
  url = data.aws_eks_cluster.this.identity[0].oidc[0].issuer
}

# The master secret lives with the writer, in the primary region. Every region reads it from there.
data "aws_db_instance" "primary" {
  region                 = local.primary_region
  db_instance_identifier = local.primary_cluster_name
}

# Read-only deploy key Argo CD uses to pull this repo, replicated to every region.
data "aws_secretsmanager_secret" "repo_ssh_key" {
  name = local.repo_ssh_secret_name
}

module "identity" {
  source = "git::https://github.com/elvin159/terraform-aws-identity.git?ref=45396f363d586d257e60a4499cec1b1822c34c12"

  cluster_name      = local.cluster_name
  oidc_provider_arn = data.aws_iam_openid_connect_provider.this.arn

  cluster_autoscaler = {
    enabled = true
  }

  aws_load_balancer_controller = {
    enabled = true
  }

  external_dns = {
    enabled         = true
    hosted_zone_ids = [local.hosted_zone_id]
  }

  external_secrets = {
    enabled = true
    secrets_manager_arns = [
      data.aws_db_instance.primary.master_user_secret[0].secret_arn,
      data.aws_secretsmanager_secret.repo_ssh_key.arn,
    ]
    kms_key_arns = [data.aws_db_instance.primary.master_user_secret[0].kms_key_id]
  }
}
