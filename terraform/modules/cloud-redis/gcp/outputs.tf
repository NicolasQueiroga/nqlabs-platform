output "host" {
  description = "Memorystore Redis instance IP address."
  value       = google_redis_instance.this.host
}

output "port" {
  description = "Memorystore Redis port."
  value       = google_redis_instance.this.port
}

output "secret_id" {
  description = "Secret Manager secret ID containing Redis connection info."
  value       = google_secret_manager_secret.redis.secret_id
}
