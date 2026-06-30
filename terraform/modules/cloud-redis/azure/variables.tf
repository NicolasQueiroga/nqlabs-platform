variable "service_name" {
  description = "Service name. Used to name the Redis Cache instance."
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
  description = "Azure resource group where the Redis Cache is created."
  type        = string
}

variable "location" {
  description = "Azure region (e.g. eastus)."
  type        = string
}

variable "tier" {
  description = "Redis tier: small (Basic C0), standard (Standard C1), large (Premium P1)."
  type        = string
  default     = "small"

  validation {
    condition     = contains(["small", "standard", "large"], var.tier)
    error_message = "tier must be small, standard, or large."
  }
}

variable "key_vault_id" {
  description = "Azure Key Vault resource ID (from cloud-secrets azure output) to store connection info."
  type        = string
}
