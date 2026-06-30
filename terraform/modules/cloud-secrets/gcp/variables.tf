variable "project" {
  description = "GCP project ID in which secrets are created."
  type        = string
}

variable "service_name" {
  description = "Service name. Used to namespace secret resource IDs."
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

variable "service_account_email" {
  description = "GCP service account email granted secretAccessor on every managed secret. Typically the output of the cloud-iam/gcp module."
  type        = string
}

variable "secrets" {
  description = "List of secret resources to create in Secret Manager. Values are NOT set here — only the resource shell and IAM grant."
  type = list(object({
    name        = string
    description = optional(string, "")
  }))
  default = []
}
