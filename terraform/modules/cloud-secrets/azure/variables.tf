variable "service_name" {
  description = "Service name. Used to name the Key Vault: kv-<service>-<environment> (max 24 chars — truncated automatically)."
  type        = string
}

variable "environment" {
  description = "Environment name (staging or production)."
  type        = string

  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "environment must be 'staging' or 'production'."
  }
}

variable "resource_group_name" {
  description = "Name of the Azure resource group in which the Key Vault is created."
  type        = string
}

variable "location" {
  description = "Azure region for the Key Vault (e.g. eastus, westeurope)."
  type        = string
}

variable "identity_client_id" {
  description = "Client ID of the User Assigned Managed Identity (from cloud-iam/azure). Used to look up the object_id for the access policy."
  type        = string
}

variable "tenant_id" {
  description = "Azure AD tenant ID (from cloud-iam/azure output or data.azurerm_client_config.current.tenant_id)."
  type        = string
}
