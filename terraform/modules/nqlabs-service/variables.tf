variable "name" {
  description = "Service name. Must match the apps/<service> directory and Kubernetes name conventions."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*$", var.name))
    error_message = "Service name must be lowercase DNS-1123 style: letters, numbers, and hyphens."
  }
}

variable "apps_root" {
  description = "Path to the repository apps/ directory where generated environment files are written."
  type        = string
}

variable "base_domain" {
  description = "Base internal service domain. Route hosts default to <service>.<environment>.<base_domain>."
  type        = string
  default     = "nqlabs.network"
}

variable "chart_value_file_prefix" {
  description = "Prefix used in argocd.valueFile. Usually apps/<service>/environments/<env>.yaml from repo root."
  type        = string
  default     = "apps"
}

variable "environments" {
  description = "Environment definitions to generate under apps/<service>/environments/."
  type = map(object({
    namespace          = optional(string)
    argocd_project     = optional(string)
    replica_count      = optional(number, 1)
    image_repository   = string
    image_tag          = string
    image_pull_policy  = optional(string, "IfNotPresent")
    image_pull_secrets = optional(list(string), [])
    container_port     = optional(number, 80)
    service_port       = optional(number, 80)
    rollout_enabled    = optional(bool, true)
    rollout_canary = optional(object({
      max_surge       = optional(string, "25%")
      max_unavailable = optional(string, "0")
    }), {})
    resource_quota = optional(object({
      enabled = optional(bool, false)
      hard    = optional(map(string), {})
    }), {})
    limit_range = optional(object({
      enabled         = optional(bool, false)
      default         = optional(map(string), {})
      default_request = optional(map(string), {})
      max             = optional(map(string), {})
      min             = optional(map(string), {})
    }), {})
    rbac = optional(object({
      create = optional(bool, false)
      rules = optional(list(object({
        api_groups = list(string)
        resources  = list(string)
        verbs      = list(string)
      })), [])
    }), {})
    cilium_network_policy = optional(object({
      enabled              = optional(bool, false)
      default_deny_ingress = optional(bool, true)
      default_deny_egress  = optional(bool, false)
      ingress              = optional(any, [])
      egress               = optional(any, [])
      ingress_deny         = optional(any, [])
      egress_deny          = optional(any, [])
    }), {})
    route_enabled = optional(bool, true)
    route_host    = optional(string)
  }))

  validation {
    condition = alltrue([
      for env_name, _ in var.environments : contains(["staging", "production"], env_name)
    ])
    error_message = "Only staging and production environments are supported by the Phase 0 service factory."
  }
}
