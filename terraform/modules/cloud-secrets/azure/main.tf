data "azurerm_client_config" "current" {}

# Look up the object_id of the managed identity by its client_id so we can
# create an access policy without requiring the caller to supply it separately.
data "azurerm_user_assigned_identity" "workload" {
  # The identity name follows the convention set by cloud-iam/azure:
  # <service>-<environment>
  name                = "${var.service_name}-${var.environment}"
  resource_group_name = var.resource_group_name
}

locals {
  # Key Vault names must be 3-24 chars, globally unique, alphanumeric + hyphens.
  # Truncate to 24 chars: kv-<service>-<env> → kv-<service[:15]>-<env[:4]>
  vault_name = substr(
    "kv-${var.service_name}-${var.environment}",
    0,
    24
  )
}

resource "azurerm_key_vault" "this" {
  name                = local.vault_name
  location            = var.location
  resource_group_name = var.resource_group_name
  tenant_id           = var.tenant_id
  sku_name            = "standard"

  # Lab settings: shorter retention, no purge protection so the vault can be
  # destroyed cleanly during iteration. Set to true for real production.
  soft_delete_retention_days = 7
  purge_protection_enabled   = false

  tags = {
    service     = var.service_name
    environment = var.environment
  }
}

# Grant the workload managed identity get + list on secrets.
resource "azurerm_key_vault_access_policy" "workload" {
  key_vault_id = azurerm_key_vault.this.id
  tenant_id    = var.tenant_id
  object_id    = data.azurerm_user_assigned_identity.workload.principal_id

  secret_permissions = [
    "Get",
    "List",
  ]
}
