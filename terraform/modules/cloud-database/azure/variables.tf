variable "service_name" {
  description = "Service name. Used to derive resource names and the database/user name."
  type        = string
}

variable "environment" {
  description = "Deployment environment (staging or production)."
  type        = string

  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "environment must be staging or production."
  }
}

variable "resource_group_name" {
  description = "Azure resource group in which all resources are created."
  type        = string
}

variable "location" {
  description = "Azure region (e.g. eastus, westeurope)."
  type        = string
}

variable "tier" {
  description = "Instance size tier. small = B_Standard_B1ms, standard = GP_Standard_D2s_v3, large = GP_Standard_D4s_v3."
  type        = string
  default     = "small"

  validation {
    condition     = contains(["small", "standard", "large"], var.tier)
    error_message = "tier must be small, standard, or large."
  }
}

variable "delegated_subnet_id" {
  description = "Optional subnet ID delegated to Microsoft.DBforPostgreSQL/flexibleServers for VNet injection."
  type        = string
  default     = null
}

variable "private_dns_zone_id" {
  description = "Optional private DNS zone resource ID required when using delegated_subnet_id."
  type        = string
  default     = null
}

variable "key_vault_id" {
  description = "Azure Key Vault resource ID (from cloud-secrets/azure) where the connection secret is stored."
  type        = string
}

variable "identity_object_id" {
  description = "Object ID of the managed identity (from cloud-iam/azure) granted Key Vault get/list on secrets."
  type        = string
}
