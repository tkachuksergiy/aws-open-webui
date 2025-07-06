output "url" {
  value = aws_lb.alb.dns_name
}

output "mcpo_url" {
  value = "https://${aws_lb.alb.dns_name}/mcpo"
  description = "URL for accessing the MCPO service"
}

output "mcpo_api_key" {
  value       = nonsensitive(aws_secretsmanager_secret_version.mcpo_api_key_secret_version.secret_string)
  sensitive   = false
  description = "API key for MCPO service authentication"
}