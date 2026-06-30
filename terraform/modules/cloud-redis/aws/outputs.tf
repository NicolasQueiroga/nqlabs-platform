output "endpoint" {
  description = "Primary endpoint address of the ElastiCache replication group."
  value       = aws_elasticache_replication_group.this.primary_endpoint_address
}

output "port" {
  description = "Redis port."
  value       = 6379
}

output "secret_arn" {
  description = "Secrets Manager ARN containing Redis connection info."
  value       = aws_secretsmanager_secret.redis.arn
}
