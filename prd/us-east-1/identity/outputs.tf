output "cluster_autoscaler_role_arn" {
  description = "Cluster Autoscaler IRSA role ARN."
  value       = module.identity.cluster_autoscaler_role_arn
}

output "aws_load_balancer_controller_role_arn" {
  description = "AWS Load Balancer Controller IRSA role ARN."
  value       = module.identity.aws_load_balancer_controller_role_arn
}

output "external_dns_role_arn" {
  description = "ExternalDNS IRSA role ARN."
  value       = module.identity.external_dns_role_arn
}

output "external_secrets_role_arn" {
  description = "External Secrets Operator IRSA role ARN."
  value       = module.identity.external_secrets_role_arn
}
