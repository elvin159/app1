variable "environment" {
  description = "Environment this root deploys to, from its folder name."
  type        = string
}

variable "config" {
  description = "The environment's env.yaml. Only the attributes below are used."
  type = object({
    account_id     = string
    primary_region = string
    regions        = map(any)
    force_destroy  = bool
    promotion = object({
      source_account_id = string
      target_account_id = string
    })
    domain         = string
    hosted_zone_id = string
    deploy_subject = string
  })
}
