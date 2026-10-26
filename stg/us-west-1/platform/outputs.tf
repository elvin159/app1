output "app_urls" {
  description = "App URLs. Every region serves the same hostnames; Route53 latency routing picks the closest."
  value       = { for app in local.apps : app => "https://${app}.${local.domain}" }
}

output "app_database_hosts" {
  description = "Database host each app connects to in this region."
  value       = { for app, db in data.aws_db_instance.app : app => db.address }
}
