variable "project" {
  description = "GCP project ID in which the Cloud SQL instance is created."
  type        = string
}

variable "region" {
  description = "GCP region for the Cloud SQL instance (e.g. us-central1)."
  type        = string
}

variable "service_name" {
  description = "Service name. Used to derive resource names and the database/user name."
  type        = string
}

variable "environment" {
  description = "Deployment environment (staging or production). Affects resource naming."
  type        = string

  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "environment must be staging or production."
  }
}

variable "tier" {
  description = "Instance size tier. small = db-f1-micro (zonal), standard = db-n1-standard-2 (regional HA), large = db-n1-standard-4 (regional HA)."
  type        = string
  default     = "small"

  validation {
    condition     = contains(["small", "standard", "large"], var.tier)
    error_message = "tier must be small, standard, or large."
  }
}

variable "deletion_protection" {
  description = "Enable deletion protection on the Cloud SQL instance. Disable before destroying."
  type        = bool
  default     = true
}

variable "service_account_email" {
  description = "GCP service account email (from cloud-iam/gcp) granted secretAccessor on the connection secret."
  type        = string
}
