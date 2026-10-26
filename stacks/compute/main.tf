locals {
  cluster_name = var.config.regions[var.region].cluster_name

  # Roles created during account bootstrap.
  admin_role_arn = "arn:aws:iam::${var.config.account_id}:role/platform-admin"
  plan_role_arn  = "arn:aws:iam::${var.config.account_id}:role/github-terraform-plan"
  apply_role_arn = "arn:aws:iam::${var.config.account_id}:role/github-terraform-apply"
}

# VPC and private subnets from the networking stack, found by tags.
data "aws_vpc" "this" {
  tags = { Name = local.cluster_name }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.this.id]
  }

  tags = { "kubernetes.io/role/internal-elb" = "1" }
}

module "compute" {
  source = "git::https://github.com/elvin159/terraform-aws-compute.git?ref=18476b736bf8ba8ac44aac0c2036e69052cf8e7a"

  cluster_name       = local.cluster_name
  kubernetes_version = var.config.compute.kubernetes_version
  subnet_ids         = sort(data.aws_subnets.private.ids)
  protection         = var.config.protection

  # The platform stack installs Helm charts from the self-hosted runner, so the public endpoint
  # is open to that runner's egress IP only. Nodes use the private endpoint.
  endpoint_public_access       = true
  endpoint_public_access_cidrs = [var.config.runner_egress_cidr]

  access_entries = {
    platform-admin = {
      principal_arn = local.admin_role_arn
      policy        = "AmazonEKSClusterAdminPolicy"
    }
    # terraform apply of the platform stack installs cluster-wide controllers.
    github-terraform-apply = {
      principal_arn = local.apply_role_arn
      policy        = "AmazonEKSClusterAdminPolicy"
    }
  }

  node_groups = {
    general = {
      instance_types = var.config.compute.node_instance_types
      capacity_type  = var.config.compute.node_capacity_type
      min_size       = var.config.compute.node_min_size
      max_size       = var.config.compute.node_max_size
    }
  }

  cluster_log_retention_days   = var.config.log_retention_days
  kms_key_deletion_window_days = var.config.kms_key_deletion_window_days
}

# terraform plan of the platform stack reads Helm release state, which Helm stores in Secrets.
# AmazonEKSAdminViewPolicy is read-only, including Secrets. The module only accepts the four
# common policies, so this entry is declared here.
resource "aws_eks_access_entry" "plan" {
  cluster_name  = module.compute.cluster_name
  principal_arn = local.plan_role_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "plan" {
  cluster_name  = module.compute.cluster_name
  principal_arn = aws_eks_access_entry.plan.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminViewPolicy"

  access_scope {
    type = "cluster"
  }
}
