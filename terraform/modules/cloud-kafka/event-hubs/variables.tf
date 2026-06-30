variable "service_name" {
  description = "Service name. Used to prefix Event Hubs namespace and authorization rule names."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*$", var.service_name))
    error_message = "service_name must be lowercase DNS-1123 style."
  }
}

variable "environment" {
  description = "Deployment environment: staging or production."
  type        = string
}

variable "resource_group_name" {
  description = "Azure resource group in which to create all resources."
  type        = string
}

variable "location" {
  description = "Azure region (e.g. eastus)."
  type        = string
}

variable "topics" {
  description = "Event Hubs (Kafka topics) to create within the namespace."
  type = list(object({
    name       = string
    partitions = optional(number, 4)
  }))
  default = []
}

variable "retention_days" {
  description = "Message retention in days for all Event Hubs (1-90 for Premium)."
  type        = number
  default     = 7

  validation {
    condition     = var.retention_days >= 1 && var.retention_days <= 90
    error_message = "retention_days must be between 1 and 90."
  }
}

variable "capacity" {
  description = "Event Hubs Premium namespace capacity units (1-8)."
  type        = number
  default     = 1
}
