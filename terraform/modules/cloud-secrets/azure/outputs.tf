output "key_vault_id" {
  description = "Resource ID of the Azure Key Vault."
  value       = azurerm_key_vault.this.id
}

output "key_vault_uri" {
  description = "URI of the Azure Key Vault (used as the vault_uri in ESO SecretStore)."
  value       = azurerm_key_vault.this.vault_uri
}
