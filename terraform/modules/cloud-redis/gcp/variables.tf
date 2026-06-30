variable "project" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "GCP region where the Memorystore instance is created (e.g. us-central1)."
  type        = string
}

variable "service_name" {
  description = "Service name. Used to name the Redis instance and secret."
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

variable "tier" {
  description = "Redis tier: small (BASIC, 1 GB) or standard (STANDARD_HA, 2 GB, replicated)."
  type        = string
  default     = "small"

  validation {
    condition     = contains(["small", "standard"], var.tier)
    error_message = "tier must be small or standard."
  }
}

variable "service_account_email" {
  description = "GCP service account email (from cloud-iam gcp output) granted Secret Manager access."
  type        = string
}

variable "authorized_network" {
  description = "VPC network self-link to authorize for Memorystore (e.g. projects/my-project/global/networks/default)."
  type        = string
  default     = ""
}
