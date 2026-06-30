locals {
  name = "${var.service_name}-${var.environment}"

  sku_map = {
    small    = "B_Standard_B1ms"
    standard = "GP_Standard_D2s_v3"
    large    = "GP_Standard_D4s_v3"
  }

  ha_mode    = var.tier != "small" ? "ZoneRedundant" : "Disabled"
  sku_name   = local.sku_map[var.tier]
  db_name    = replace(var.service_name, "-", "_")
  admin_user = replace(var.service_name, "-", "_")

  secret_name = "${var.service_name}-${var.environment}-db"
}

resource "random_password" "db" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "azurerm_postgresql_flexible_server" "main" {
  name                = local.name
  resource_group_name = var.resource_group_name
  location            = var.location

  version    = "17"
  sku_name   = local.sku_name
  storage_mb = 32768

  administrator_login    = local.admin_user
  administrator_password = random_password.db.result

  backup_retention_days        = 7
  geo_redundant_backup_enabled = var.tier != "small"

  # VNet injection (optional). Both must be provided together.
  delegated_subnet_id = var.delegated_subnet_id
  private_dns_zone_id = var.private_dns_zone_id

  dynamic "high_availability" {
    for_each = local.ha_mode != "Disabled" ? [1] : []
    content {
      mode = local.ha_mode
    }
  }

  tags = {
    service     = var.service_name
    environment = var.environment
    managed_by  = "terraform"
  }
}

resource "azurerm_postgresql_flexible_server_database" "main" {
  name      = local.db_name
  server_id = azurerm_postgresql_flexible_server.main.id
  charset   = "utf8"
  collation = "en_US.utf8"
}

# Key Vault access policy: grant the managed identity get + list on secrets.
data "azurerm_key_vault" "main" {
  name                = regex("vaults/([^/]+)$", var.key_vault_id)[0]
  resource_group_name = var.resource_group_name
}

resource "azurerm_key_vault_access_policy" "db_identity" {
  key_vault_id = var.key_vault_id
  tenant_id    = data.azurerm_key_vault.main.tenant_id
  object_id    = var.identity_object_id

  secret_permissions = ["Get", "List"]
}

# Store the connection details in Key Vault.
resource "azurerm_key_vault_secret" "connection" {
  name         = local.secret_name
  key_vault_id = var.key_vault_id

  value = jsonencode({
    username       = local.admin_user
    password       = random_password.db.result
    host           = azurerm_postgresql_flexible_server.main.fqdn
    database       = local.db_name
    connection_url = "postgresql://${local.admin_user}:${random_password.db.result}@${azurerm_postgresql_flexible_server.main.fqdn}:5432/${local.db_name}?sslmode=require"
  })

  tags = {
    service     = var.service_name
    environment = var.environment
    managed_by  = "terraform"
  }

  depends_on = [azurerm_key_vault_access_policy.db_identity]
}
