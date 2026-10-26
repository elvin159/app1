locals {
  apps            = ["backend", "frontend"]
  environment     = var.environment
  account_id      = var.config.account_id
  region          = var.config.primary_region # images are pushed here
  replica_regions = [for r in keys(var.config.regions) : r if r != var.config.primary_region]
  force_destroy   = var.config.force_destroy

  promotion_source_account_id = var.config.promotion.source_account_id
  promotion_target_account_id = var.config.promotion.target_account_id

  github_subject = var.config.deploy_subject
  static_domain  = "static.${var.config.domain}"
  hosted_zone_id = var.config.hosted_zone_id

  ecr_lifecycle_policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the last 50 images"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 50 }
      action       = { type = "expire" }
    }]
  })
}

# The app pipelines push images and static assets with the roles in github.tf. They trust the
# account's GitHub OIDC provider (bootstrap) and only this environment's GitHub subject.
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}
