output "server_name" {
  description = "Azure Database for PostgreSQL Flexible Server name."
  value       = azurerm_postgresql_flexible_server.main.name
}

output "server_fqdn" {
  description = "Fully qualified domain name of the PostgreSQL server."
  value       = azurerm_postgresql_flexible_server.main.fqdn
}

output "database_name" {
  description = "PostgreSQL database name created for the service."
  value       = azurerm_postgresql_flexible_server_database.main.name
}

output "key_vault_secret_id" {
  description = "Key Vault secret resource ID holding the connection details."
  value       = azurerm_key_vault_secret.connection.id
}

output "key_vault_secret_name" {
  description = "Key Vault secret name."
  value       = azurerm_key_vault_secret.connection.name
}
