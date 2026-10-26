locals {
  cluster_name = var.config.regions[var.region].cluster_name
  is_primary   = var.region == var.config.primary_region

  # Database instances in this region: the writer and its read replica in the primary region, the
  # cross-region replica elsewhere.
  db_instances = local.is_primary ? {
    writer = local.cluster_name
    read1  = "${local.cluster_name}-read1"
  } : { replica = local.cluster_name }
  db_replicas = local.is_primary ? { read1 = "${local.cluster_name}-read1" } : { replica = local.cluster_name }
}

module "observability" {
  source = "git::https://github.com/elvin159/terraform-aws-observability.git?ref=1b3d393b9ca3d0bec48bf5fd69c53dc3e5c7399f"

  name         = local.cluster_name
  alarm_emails = var.config.alarm_emails

  alarms = merge(
    { for role, id in local.db_instances : "rds-${role}-cpu-high" => {
      description         = "${id}: CPU above 80% for 15 minutes."
      namespace           = "AWS/RDS"
      metric_name         = "CPUUtilization"
      dimensions          = { DBInstanceIdentifier = id }
      statistic           = "Average"
      comparison_operator = "GreaterThanThreshold"
      threshold           = 80
      evaluation_periods  = 3
    } },
    { for role, id in local.db_instances : "rds-${role}-storage-low" => {
      description         = "${id}: free storage below 2 GiB."
      namespace           = "AWS/RDS"
      metric_name         = "FreeStorageSpace"
      dimensions          = { DBInstanceIdentifier = id }
      statistic           = "Minimum"
      comparison_operator = "LessThanThreshold"
      threshold           = 2 * 1024 * 1024 * 1024
    } },
    { for role, id in local.db_replicas : "rds-${role}-replica-lag" => {
      description         = "${id}: replica more than 60 seconds behind the writer for 15 minutes."
      namespace           = "AWS/RDS"
      metric_name         = "ReplicaLag"
      dimensions          = { DBInstanceIdentifier = id }
      statistic           = "Maximum"
      comparison_operator = "GreaterThanThreshold"
      threshold           = 60
      evaluation_periods  = 3
    } },
  )
}
