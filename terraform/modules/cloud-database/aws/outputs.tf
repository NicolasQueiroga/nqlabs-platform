output "endpoint" {
  description = "RDS instance endpoint (host:port)."
  value       = aws_db_instance.main.endpoint
}

output "port" {
  description = "RDS instance port."
  value       = aws_db_instance.main.port
}

output "database_name" {
  description = "PostgreSQL database name created for the service."
  value       = aws_db_instance.main.db_name
}

output "secret_arn" {
  description = "Secrets Manager secret ARN holding the connection details."
  value       = aws_secretsmanager_secret.connection.arn
}

output "secret_name" {
  description = "Secrets Manager secret name (path)."
  value       = aws_secretsmanager_secret.connection.name
}

output "security_group_id" {
  description = "Security group ID attached to the RDS instance."
  value       = aws_security_group.rds.id
}
