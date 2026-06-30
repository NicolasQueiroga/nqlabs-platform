variable "service_name" {
  description = "Service name. Used to name the Confluent service account, ACLs, and API key."
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

variable "cloud_provider" {
  description = "Cloud provider for the Confluent Kafka cluster: GCP, AWS, or AZURE."
  type        = string
  default     = "GCP"

  validation {
    condition     = contains(["GCP", "AWS", "AZURE"], var.cloud_provider)
    error_message = "cloud_provider must be GCP, AWS, or AZURE."
  }
}

variable "region" {
  description = "Region for the Confluent Kafka cluster (must be valid for the chosen cloud_provider)."
  type        = string
}

variable "tier" {
  description = "Cluster tier: basic (shared) or dedicated (single-tenant, 1 CKU)."
  type        = string
  default     = "basic"

  validation {
    condition     = contains(["basic", "dedicated"], var.tier)
    error_message = "tier must be basic or dedicated."
  }
}

variable "topics" {
  description = "Kafka topics to create and grant the service account access to."
  type = list(object({
    name       = string
    partitions = optional(number, 6)
    config     = optional(map(string), {})
  }))
  default = []
}

variable "confluent_environment_id" {
  description = "Existing Confluent environment ID. If empty, a new environment is created."
  type        = string
  default     = ""
}
