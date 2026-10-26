variable "region" {
  description = "Region this root deploys to, from its folder name."
  type        = string
}

variable "config" {
  description = "The environment's env.yaml. Only the attributes below are used."
  type = object({
    regions = map(object({
      cluster_name = string
      vpc_cidr     = string
      az_count     = number
    }))
    log_retention_days = number
    networking = object({
      single_nat_gateway = bool
    })
  })
}
