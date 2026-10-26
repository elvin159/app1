locals {
  cluster_name         = var.config.regions[var.region].cluster_name
  primary_cluster_name = var.config.regions[var.config.primary_region].cluster_name
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
  region                 = var.config.primary_region
  db_instance_identifier = local.primary_cluster_name
}

# Read-only deploy key Argo CD uses to pull this repo, replicated to every region.
data "aws_secretsmanager_secret" "repo_ssh_key" {
  name = var.config.argocd_repo_ssh_secret
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
    hosted_zone_ids = [var.config.hosted_zone_id]
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
