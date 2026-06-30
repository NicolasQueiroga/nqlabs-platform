variable "project" {
  description = "GCP project ID in which to create the service account and IAM bindings."
  type        = string
}

variable "service_name" {
  description = "Service name. Used as the SA account ID and in resource naming."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.service_name))
    error_message = "service_name must be 6-30 chars, lowercase letters, digits, and hyphens, start with a letter."
  }
}

variable "environment" {
  description = "Target environment (staging or production). Used as a resource label."
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
  description = "Kubernetes ServiceAccount name that will impersonate this GCP SA. Defaults to service_name."
  type        = string
  default     = ""
}

variable "roles" {
  description = "List of IAM role IDs to bind to the service account (e.g. roles/storage.objectViewer)."
  type        = list(string)
  default     = []
}

variable "cluster_name" {
  description = "GKE cluster name. Used to build the Workload Identity pool provider display name."
  type        = string
}

variable "cluster_location" {
  description = "GKE cluster region or zone (e.g. us-central1)."
  type        = string
}

variable "workload_identity_pool_id" {
  description = "Existing Workload Identity pool ID to use. Required when create_pool = false."
  type        = string
  default     = ""
}

variable "create_pool" {
  description = "Set true exactly once per GKE cluster to create the Workload Identity pool and OIDC provider. Subsequent services in the same cluster set this to false and supply workload_identity_pool_id."
  type        = bool
  default     = false
}
