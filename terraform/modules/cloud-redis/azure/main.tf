locals {
  name = "${var.service_name}-${var.environment}"

  sku_name = {
    small    = "Basic"
    standard = "Standard"
    large    = "Premium"
  }[var.tier]

  family = var.tier == "large" ? "P" : "C"

  capacity = {
    small    = 0
    standard = 1
    large    = 1
  }[var.tier]

  kv_secret_name = "${var.service_name}-${var.environment}-redis"
}

resource "azurerm_redis_cache" "this" {
  name                = local.name
  resource_group_name = var.resource_group_name
  location            = var.location

  sku_name = local.sku_name
  family   = local.family
  capacity = local.capacity

  enable_non_ssl_port = false
  minimum_tls_version = "1.2"
  redis_version       = "7"

  tags = {
    service     = var.service_name
    environment = var.environment
    managed-by  = "terraform"
  }
}

resource "azurerm_key_vault_secret" "redis" {
  name         = local.kv_secret_name
  key_vault_id = var.key_vault_id

  value = jsonencode({
    hostname   = azurerm_redis_cache.this.hostname
    port       = tostring(azurerm_redis_cache.this.ssl_port)
    password   = azurerm_redis_cache.this.primary_access_key
    redis_url  = "rediss://:${azurerm_redis_cache.this.primary_access_key}@${azurerm_redis_cache.this.hostname}:${azurerm_redis_cache.this.ssl_port}"
  })
}
