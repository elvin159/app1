locals {
  environment          = var.environment
  account_id           = var.config.account_id
  region               = var.region
  cluster_name         = var.config.regions[var.region].cluster_name
  primary_region       = var.config.primary_region
  primary_cluster_name = var.config.regions[var.config.primary_region].cluster_name
  is_primary           = var.region == var.config.primary_region

  domain               = var.config.domain
  hosted_zone_id       = var.config.hosted_zone_id
  repo_ssh_url         = "git@github.com:${var.config.github_repo}.git"
  repo_ssh_secret_name = var.config.argocd_repo_ssh_secret

  # Kubernetes name of each app's workloads.
  apps = {
    backend  = "backend-api"
    frontend = "frontend"
  }
}

data "aws_eks_cluster" "this" {
  name = local.cluster_name
}

# IRSA roles from the identity stack.
data "aws_iam_role" "irsa" {
  for_each = toset(["aws-load-balancer-controller", "external-dns", "external-secrets", "cluster-autoscaler"])

  name = "${local.cluster_name}-${each.key}"
}

# The writer holds the database name and the master secret.
data "aws_db_instance" "primary" {
  region                 = local.primary_region
  db_instance_identifier = local.primary_cluster_name
}

# The local instance each app connects to: the backend reads from a read replica; the frontend uses
# the writer where it is local, and this region's replica elsewhere.
data "aws_db_instance" "app" {
  for_each = {
    backend  = local.is_primary ? "${local.cluster_name}-read1" : local.cluster_name
    frontend = local.cluster_name
  }

  db_instance_identifier = each.value
}
