locals {
  cluster_name         = var.config.regions[var.region].cluster_name
  primary_cluster_name = var.config.regions[var.config.primary_region].cluster_name
  is_primary           = var.region == var.config.primary_region

  # The writer's backups are copied to the environment's next region, if it has one.
  backup_replication_region = try([for r in keys(var.config.regions) : r if r != var.config.primary_region][0], null)
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

  region                 = var.config.primary_region
  db_instance_identifier = local.primary_cluster_name
}

module "database" {
  source = "git::https://github.com/elvin159/terraform-aws-database.git?ref=71fc1bb184a73a448a868cb899f7581605378dd5"

  name       = local.cluster_name
  vpc_id     = data.aws_vpc.this.id
  subnet_ids = sort(data.aws_subnets.private.ids)
  protection = var.config.protection

  # Only this region's cluster can connect.
  allowed_security_group_ids = [data.aws_eks_cluster.this.vpc_config[0].cluster_security_group_id]

  engine_version        = "17"
  instance_class        = var.config.database.instance_class
  multi_az              = var.config.database.multi_az
  allocated_storage     = var.config.database.allocated_storage
  max_allocated_storage = var.config.database.max_allocated_storage

  # Primary region: the writer, a read replica for read traffic, and backup copies in another region.
  database_name = local.is_primary ? "app1" : null
  read_replicas = { for k in(local.is_primary ? ["read1"] : []) : k => {} }
  backup_replication = local.is_primary && local.backup_replication_region != null ? {
    region         = local.backup_replication_region
    retention_days = var.config.database.backup_retention_days
  } : null

  # Other regions: a cross-region read replica of the writer.
  replicate_source_db = local.is_primary ? null : data.aws_db_instance.primary[0].db_instance_arn

  backup_retention_days        = var.config.database.backup_retention_days
  apply_immediately            = var.config.database.apply_immediately
  log_retention_days           = var.config.log_retention_days
  kms_key_deletion_window_days = var.config.kms_key_deletion_window_days
}
