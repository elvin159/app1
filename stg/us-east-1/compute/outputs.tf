output "cluster_name" {
  description = "EKS cluster name."
  value       = module.compute.cluster_name
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint."
  value       = module.compute.cluster_endpoint
}

output "cluster_security_group_id" {
  description = "Cluster security group, used by nodes and pods."
  value       = module.compute.cluster_security_group_id
}

output "oidc_provider_arn" {
  description = "IAM OIDC provider ARN, used by the identity stack."
  value       = module.compute.oidc_provider_arn
}
