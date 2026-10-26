output "identifier" {
  description = "DB instance identifier: the writer in the primary region, a cross-region replica elsewhere."
  value       = module.database.identifier
}

output "address" {
  description = "Hostname of this region's instance."
  value       = module.database.address
}

output "read_replica_addresses" {
  description = "Hostnames of the in-region read replicas (primary region only)."
  value       = module.database.read_replica_addresses
}

output "master_user_secret_arn" {
  description = "Master credentials secret (primary region only; replicas use the writer's)."
  value       = module.database.master_user_secret_arn
}
