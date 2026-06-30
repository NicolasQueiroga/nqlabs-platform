output "namespace_name" {
  description = "Event Hubs namespace name."
  value       = azurerm_eventhub_namespace.this.name
}

output "kafka_endpoint" {
  description = "Kafka-compatible bootstrap endpoint (hostname:9093)."
  value       = "${azurerm_eventhub_namespace.this.name}.servicebus.windows.net:9093"
}

output "connection_string" {
  description = "Primary connection string for the service authorization rule. Use as the Kafka SASL/PLAIN password."
  value       = azurerm_eventhub_namespace_authorization_rule.service.primary_connection_string
  sensitive   = true
}

output "event_hub_names" {
  description = "List of created Event Hub (topic) names."
  value       = keys(azurerm_eventhub.topics)
}
