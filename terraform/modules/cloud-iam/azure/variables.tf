variable "service_name" {
  description = "Service name. Used as the managed identity name suffix."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.service_name))
    error_message = "service_name must be lowercase, start with a letter, and contain only letters, digits, and hyphens."
  }
}

variable "environment" {
  description = "Target environment (staging or production). Appended to the managed identity name."
  type        = string

  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "environment must be staging or production."
  }
}

variable "namespace" {
  description = "Kubernetes namespace where the workload runs."
  type        = string
}

variable "k8s_sa_name" {
  description = "Kubernetes ServiceAccount name. Defaults to service_name."
  type        = string
  default     = ""
}

variable "resource_group_name" {
  description = "Azure resource group in which to create the managed identity."
  type        = string
}

variable "location" {
  description = "Azure region for the managed identity (e.g. eastus)."
  type        = string
}

variable "aks_oidc_issuer_url" {
  description = "AKS cluster OIDC issuer URL. Retrieve with: az aks show --query oidcIssuerProfile.issuerUrl."
  type        = string
}

variable "role_assignments" {
  description = "List of Azure role assignments to apply to the managed identity."
  type = list(object({
    scope                = string
    role_definition_name = string
  }))
  default = []
}
