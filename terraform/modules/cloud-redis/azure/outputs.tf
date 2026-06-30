output "hostname" {
  description = "Azure Cache for Redis hostname."
  value       = azurerm_redis_cache.this.hostname
}

output "port" {
  description = "Azure Cache for Redis SSL port."
  value       = azurerm_redis_cache.this.ssl_port
}

output "key_vault_secret_id" {
  description = "Key Vault secret ID containing Redis connection info."
  value       = azurerm_key_vault_secret.redis.id
}
