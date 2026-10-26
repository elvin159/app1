locals {
  environment  = "prd"
  account_id   = "333333333333"
  region       = "us-west-1"
  cluster_name = "app1-prd-usw1"

  protection                   = "strict"
  node_instance_types          = ["m7i.large", "m6i.large"]
  node_capacity_type           = "ON_DEMAND"
  node_min_size                = 3
  node_max_size                = 10
  log_retention_days           = 365
  kms_key_deletion_window_days = 30

  # Bootstrap prerequisites (stub values).
  runner_egress_cidr = "203.0.113.30/32"
  admin_role_arn     = "arn:aws:iam::333333333333:role/platform-admin"
  plan_role_arn      = "arn:aws:iam::333333333333:role/github-terraform-plan"
  apply_role_arn     = "arn:aws:iam::333333333333:role/github-terraform-apply"
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

  cluster_name = local.cluster_name
  # Matches the Cluster Autoscaler release installed by the platform stack.
  kubernetes_version = "1.35"
  subnet_ids         = sort(data.aws_subnets.private.ids)
  protection         = local.protection

  # The platform stack installs Helm charts from the self-hosted runner, so the public endpoint
  # is open to that runner's egress IP only. Nodes use the private endpoint.
  endpoint_public_access       = true
  endpoint_public_access_cidrs = [local.runner_egress_cidr]

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
      instance_types = local.node_instance_types
      capacity_type  = local.node_capacity_type
      min_size       = local.node_min_size
      max_size       = local.node_max_size
    }
  }

  cluster_log_retention_days   = local.log_retention_days
  kms_key_deletion_window_days = local.kms_key_deletion_window_days
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
