output "sns_topic_arn" {
  description = "Alarm topic ARN."
  value       = module.observability.sns_topic_arn
}

output "alarm_names" {
  description = "Alarm names."
  value       = module.observability.alarm_names
}
