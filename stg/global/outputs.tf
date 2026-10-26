output "ecr_repository_urls" {
  description = "ECR repository URL per app, in the primary region. Replica regions use the same path."
  value       = { for k, r in aws_ecr_repository.app : k => r.repository_url }
}

output "github_deploy_role_arns" {
  description = "IAM role ARN per app pipeline."
  value       = { for k, r in aws_iam_role.github_deploy : k => r.arn }
}

output "static_bucket_name" {
  description = "S3 bucket for the frontend static assets."
  value       = module.bucket.bucket_name
}

output "static_distribution_id" {
  description = "CloudFront distribution ID."
  value       = module.bucket.distribution_id
}

output "static_urls" {
  description = "Static site URLs."
  value       = module.bucket.urls
}
