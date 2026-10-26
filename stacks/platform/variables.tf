variable "environment" {
  description = "Environment this root deploys to, from its folder name."
  type        = string
}

variable "region" {
  description = "Region this root deploys to, from its folder name."
  type        = string
}

variable "config" {
  description = "The environment's env.yaml. Only the attributes below are used."
  type = object({
    account_id     = string
    primary_region = string
    regions = map(object({
      cluster_name = string
    }))
    apps = object({
      replicas = number
    })
    domain                 = string
    hosted_zone_id         = string
    github_repo            = string
    argocd_repo_ssh_secret = string
  })
}
