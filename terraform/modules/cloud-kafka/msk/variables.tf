variable "service_name" {
  description = "Service name. Used to name the MSK cluster and associated resources."
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

variable "vpc_id" {
  description = "VPC ID where the MSK cluster is deployed."
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for the MSK cluster. Must span at least 2 AZs for standard tier."
  type        = list(string)
}

variable "tier" {
  description = "Cluster tier: small (kafka.t3.small, 1 broker) or standard (kafka.m5.large, 3 brokers)."
  type        = string
  default     = "small"

  validation {
    condition     = contains(["small", "standard"], var.tier)
    error_message = "tier must be small or standard."
  }
}

variable "kafka_version" {
  description = "MSK Kafka version."
  type        = string
  default     = "3.7.x"
}

variable "sasl_users" {
  description = "List of SASL/SCRAM usernames to create. Passwords are auto-generated and stored in Secrets Manager."
  type        = list(string)
  default     = []
}
