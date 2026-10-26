variable "region" {
  description = "Region this root deploys to, from its folder name."
  type        = string
}

variable "config" {
  description = "The environment's env.yaml. Only the attributes below are used."
  type = object({
    primary_region = string
    regions = map(object({
      cluster_name = string
    }))
    protection                   = string
    log_retention_days           = number
    kms_key_deletion_window_days = number
    database = object({
      instance_class        = string
      multi_az              = bool
      allocated_storage     = number
      max_allocated_storage = number
      backup_retention_days = number
      apply_immediately     = bool
    })
  })
}
