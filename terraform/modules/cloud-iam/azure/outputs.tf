output "client_id" {
  description = "Client ID of the user-assigned managed identity. Set as the azure.workload.identity/client-id annotation on the Kubernetes ServiceAccount."
  value       = azurerm_user_assigned_identity.this.client_id
}

output "resource_id" {
  description = "Azure resource ID of the managed identity."
  value       = azurerm_user_assigned_identity.this.id
}

output "tenant_id" {
  description = "Azure tenant ID. Set as the azure.workload.identity/tenant-id label on the pod or namespace."
  value       = data.azurerm_client_config.current.tenant_id
}
