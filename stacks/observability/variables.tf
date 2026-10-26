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
    alarm_emails = list(string)
  })
}
