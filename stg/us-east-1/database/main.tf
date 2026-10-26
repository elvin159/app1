locals {
  environment          = "stg"
  account_id           = "222222222222"
  region               = "us-east-1"
  cluster_name         = "app1-stg-use1"
  primary_region       = "us-east-1"
  primary_cluster_name = "app1-stg-use1"
  is_primary           = local.region == local.primary_region

  protection                   = "standard"
  instance_class               = "db.m7g.large"
  multi_az                     = true
  allocated_storage            = 100
  max_allocated_storage        = 500
  backup_retention_days        = 14
  backup_replication_region    = "us-west-1" # where the writer's backups are copied
  apply_immediately            = false
  log_retention_days           = 90
  kms_key_deletion_window_days = 30
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

# Nodes and pods use the EKS cluster security group.
data "aws_eks_cluster" "this" {
  name = local.cluster_name
}

# The writer, in the primary region. Other regions replicate it.
data "aws_db_instance" "primary" {
  count = local.is_primary ? 0 : 1

  region                 = local.primary_region
  db_instance_identifier = local.primary_cluster_name
}

module "database" {
  source = "git::https://github.com/elvin159/terraform-aws-database.git?ref=52027d8ee8910ef4388e4c98d39fd94b5f45d413"

  name       = local.cluster_name
  vpc_id     = data.aws_vpc.this.id
  subnet_ids = sort(data.aws_subnets.private.ids)
  protection = local.protection

  # Only this region's cluster can connect.
  allowed_security_group_ids = [data.aws_eks_cluster.this.vpc_config[0].cluster_security_group_id]

  engine_version        = "17"
  instance_class        = local.instance_class
  multi_az              = local.multi_az
  allocated_storage     = local.allocated_storage
  max_allocated_storage = local.max_allocated_storage

  # Primary region: the writer, a read replica for read traffic, and backup copies in another region.
  database_name = local.is_primary ? "app1" : null
  read_replicas = { for k in(local.is_primary ? ["read1"] : []) : k => {} }
  backup_replication = local.is_primary && local.backup_replication_region != null ? {
    region         = local.backup_replication_region
    retention_days = local.backup_retention_days
  } : null

  # Other regions: a cross-region read replica of the writer.
  replicate_source_db = local.is_primary ? null : data.aws_db_instance.primary[0].db_instance_arn

  backup_retention_days        = local.backup_retention_days
  apply_immediately            = local.apply_immediately
  log_retention_days           = local.log_retention_days
  kms_key_deletion_window_days = local.kms_key_deletion_window_days
}
