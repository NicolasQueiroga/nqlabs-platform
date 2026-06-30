output "service_account_email" {
  description = "GCP Service Account email for the payments-example workload."
  value       = module.iam.service_account_email
}

output "db_connection_name" {
  description = "Cloud SQL connection name (for Cloud SQL Proxy sidecar)."
  value       = module.db.connection_name
}

output "db_secret_id" {
  description = "Secret Manager secret ID containing the database connection URL."
  value       = module.db.secret_id
}

output "redis_host" {
  description = "Memorystore Redis host."
  value       = module.redis.host
}

output "kafka_bootstrap_endpoint" {
  description = "Confluent Kafka bootstrap endpoint."
  value       = module.kafka.bootstrap_endpoint
}
