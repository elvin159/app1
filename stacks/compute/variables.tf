variable "region" {
  description = "Region this root deploys to, from its folder name."
  type        = string
}

variable "config" {
  description = "The environment's env.yaml. Only the attributes below are used."
  type = object({
    account_id = string
    regions = map(object({
      cluster_name = string
    }))
    protection                   = string
    log_retention_days           = number
    kms_key_deletion_window_days = number
    runner_egress_cidr           = string
    compute = object({
      kubernetes_version  = string
      node_instance_types = list(string)
      node_capacity_type  = string
      node_min_size       = number
      node_max_size       = number
    })
  })
}
