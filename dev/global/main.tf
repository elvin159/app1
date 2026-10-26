locals {
  environment     = "dev"
  account_id      = "111111111111"
  region          = "us-east-1" # primary region: images are pushed here
  replica_regions = []          # images are replicated here
  apps            = ["backend", "frontend"]
  force_destroy   = true # dev only

  # Image promotion: dev -> stg -> prd. Each environment copies the image from the previous one.
  promotion_source_account_id = null
  promotion_target_account_id = "222222222222"

  # Bootstrap prerequisites (stub values).
  github_subject = "repo:elvin159/app1:ref:refs/heads/main" # the only GitHub workflows allowed to deploy here
  static_domain  = "static.dev.example.com"
  hosted_zone_id = "Z0000000000000000DEV"

  ecr_lifecycle_policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the last 50 images"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 50 }
      action       = { type = "expire" }
    }]
  })
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

# The app pipelines push images and static assets with these roles. They trust the account's GitHub
# OIDC provider (bootstrap) and only the GitHub subject for this environment.
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}
