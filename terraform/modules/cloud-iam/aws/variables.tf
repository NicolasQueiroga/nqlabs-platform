variable "service_name" {
  description = "Service name. Used as the IAM role name suffix."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.service_name))
    error_message = "service_name must be lowercase, start with a letter, and contain only letters, digits, and hyphens."
  }
}

variable "environment" {
  description = "Target environment (staging or production). Appended to the IAM role name."
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

variable "eks_oidc_provider_url" {
  description = "EKS cluster OIDC provider URL without https:// prefix (e.g. oidc.eks.us-east-1.amazonaws.com/id/EXAMPL3)."
  type        = string
}

variable "policy_arns" {
  description = "List of IAM managed policy ARNs to attach to the role."
  type        = list(string)
  default     = []
}
