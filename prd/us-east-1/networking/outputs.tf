output "vpc_id" {
  description = "VPC ID."
  value       = module.networking.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs, one per AZ."
  value       = module.networking.private_subnet_ids
}

output "nat_public_ips" {
  description = "NAT gateway public IPs, for allow-listing outbound traffic."
  value       = module.networking.nat_public_ips
}
