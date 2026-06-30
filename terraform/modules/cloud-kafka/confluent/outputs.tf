output "bootstrap_endpoint" {
  description = "Confluent Kafka cluster bootstrap endpoint."
  value       = confluent_kafka_cluster.this.bootstrap_endpoint
}

output "cluster_id" {
  description = "Confluent Kafka cluster ID."
  value       = confluent_kafka_cluster.this.id
}

output "api_key" {
  description = "Kafka API key ID for the service account."
  value       = confluent_api_key.service.id
}

output "api_secret" {
  description = "Kafka API key secret for the service account."
  value       = confluent_api_key.service.secret
  sensitive   = true
}
