locals {
  # Namespace name: must be 6-50 chars, letters/numbers/hyphens.
  namespace_name = "${var.service_name}-${var.environment}"

  topics_map = { for t in var.topics : t.name => t }
}

# Event Hubs namespace — Premium SKU exposes a Kafka-compatible endpoint.
resource "azurerm_eventhub_namespace" "this" {
  name                = local.namespace_name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "Premium"
  capacity            = var.capacity

  # Kafka endpoint is always enabled on Premium; this flag is informational.
  # local_authentication_enabled = true (default)

  tags = {
    service     = var.service_name
    environment = var.environment
    managed-by  = "terraform"
  }
}

# One Event Hub per topic entry (Event Hub = Kafka topic in the Kafka protocol view).
resource "azurerm_eventhub" "topics" {
  for_each = local.topics_map

  name                = each.value.name
  namespace_name      = azurerm_eventhub_namespace.this.name
  resource_group_name = var.resource_group_name
  partition_count     = each.value.partitions
  message_retention   = var.retention_days
}

# Authorization rule granting LISTEN + SEND to the service.
# The connection string derived from this rule is the Kafka password for SASL/PLAIN.
resource "azurerm_eventhub_namespace_authorization_rule" "service" {
  name                = "${var.service_name}-listen-send"
  namespace_name      = azurerm_eventhub_namespace.this.name
  resource_group_name = var.resource_group_name

  listen = true
  send   = true
  manage = false
}
