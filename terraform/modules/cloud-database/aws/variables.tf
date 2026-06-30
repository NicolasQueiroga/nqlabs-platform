variable "service_name" {
  description = "Service name. Used to derive resource names and the database/user name."
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
  description = "AWS region for the RDS instance and Secrets Manager secret."
  type        = string
}

variable "tier" {
  description = "Instance size tier. small = db.t4g.micro (single-AZ), standard = db.t4g.medium (multi-AZ), large = db.t4g.large (multi-AZ)."
  type        = string
  default     = "small"

  validation {
    condition     = contains(["small", "standard", "large"], var.tier)
    error_message = "tier must be small, standard, or large."
  }
}

variable "vpc_id" {
  description = "VPC ID in which the RDS instance and security group are created."
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for the DB subnet group. Use private subnets."
  type        = list(string)
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to connect to RDS on port 5432 (e.g. pod CIDR, VPN)."
  type        = list(string)
}

variable "role_name" {
  description = "IAM role name (from cloud-iam/aws) granted access to the Secrets Manager secret."
  type        = string
}

variable "deletion_protection" {
  description = "Enable RDS deletion protection and store a final snapshot before destroy."
  type        = bool
  default     = true
}
