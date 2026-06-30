variable "service_name" {
  description = "Service name. Used to name the ElastiCache cluster and Secrets Manager secret."
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

variable "region" {
  description = "AWS region."
  type        = string
}

variable "tier" {
  description = "Redis tier: small (single-node) or standard (multi-AZ replica group)."
  type        = string
  default     = "small"

  validation {
    condition     = contains(["small", "standard"], var.tier)
    error_message = "tier must be small or standard."
  }
}

variable "vpc_id" {
  description = "VPC ID where the ElastiCache cluster is deployed."
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for the ElastiCache subnet group."
  type        = list(string)
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to reach the Redis port (6379)."
  type        = list(string)
  default     = []
}

variable "role_name" {
  description = "IAM role name (from cloud-iam aws output) granted access to the connection secret."
  type        = string
}
