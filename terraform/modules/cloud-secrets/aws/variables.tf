variable "service_name" {
  description = "Service name. Used to build the secret name path: <service>/<environment>/<name>."
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

variable "role_name" {
  description = "Name of the IAM role (from cloud-iam/aws) that receives secretsmanager access. The module creates and attaches an inline policy."
  type        = string
}

variable "region" {
  description = "AWS region where secrets are created."
  type        = string
}

variable "secrets" {
  description = "List of secret resources to create. Values are NOT set here — only the resource shell and IAM grant."
  type = list(object({
    name        = string
    description = optional(string, "")
  }))
  default = []
}
