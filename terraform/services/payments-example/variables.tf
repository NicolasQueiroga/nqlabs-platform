variable "gcp_project" {
  description = "GCP project ID."
  type        = string
}

variable "gcp_region" {
  description = "GCP region (e.g. us-central1)."
  type        = string
  default     = "us-central1"
}

variable "environment" {
  description = "Deployment environment: staging or production."
  type        = string

  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "environment must be staging or production."
  }
}

variable "image_tag" {
  description = "Container image tag to deploy."
  type        = string
}

variable "gke_cluster_name" {
  description = "Name of the GKE cluster (used to name the WIF pool provider)."
  type        = string
}

variable "workload_identity_pool_id" {
  description = "Existing WIF pool ID for the GKE cluster. Created once by the platform team."
  type        = string
}

variable "confluent_environment_id" {
  description = "Existing Confluent Cloud environment ID. Leave empty to create one."
  type        = string
  default     = ""
}
