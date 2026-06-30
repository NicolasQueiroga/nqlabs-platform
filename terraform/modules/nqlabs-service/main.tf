locals {
  normalized_environments = {
    for env_name, env in var.environments : env_name => {
      namespace             = coalesce(env.namespace, "${var.name}-${env_name}")
      argocd_project        = coalesce(env.argocd_project, "services-${env_name}")
      replica_count         = env.replica_count
      value_file            = "${var.chart_value_file_prefix}/${var.name}/environments/${env_name}.yaml"
      image_repository      = env.image_repository
      image_tag             = env.image_tag
      image_pull_policy     = env.image_pull_policy
      image_pull_secrets    = env.image_pull_secrets
      container_port        = env.container_port
      service_port          = env.service_port
      rollout_enabled       = env.rollout_enabled
      max_surge             = coalesce(env.rollout_canary.max_surge, "25%")
      max_unavailable       = coalesce(env.rollout_canary.max_unavailable, "0")
      resource_quota        = env.resource_quota
      limit_range           = env.limit_range
      rbac                  = env.rbac
      cilium_network_policy = env.cilium_network_policy
      route_enabled         = env.route_enabled
      route_host            = coalesce(env.route_host, "${var.name}.${env_name}.${var.base_domain}")
      identity              = env.identity
      database              = env.database
      redis                 = env.redis
      kafka                 = env.kafka
    }
  }
}

resource "local_file" "environment" {
  for_each = local.normalized_environments

  filename             = "${var.apps_root}/${var.name}/environments/${each.key}.yaml"
  file_permission      = "0644"
  directory_permission = "0755"

  content = templatefile("${path.module}/templates/environment.yaml.tftpl", {
    service_name          = var.name
    environment_name      = each.key
    namespace             = each.value.namespace
    argocd_project        = each.value.argocd_project
    value_file            = each.value.value_file
    replica_count         = each.value.replica_count
    image_repository      = each.value.image_repository
    image_tag             = each.value.image_tag
    image_pull_policy     = each.value.image_pull_policy
    image_pull_secrets    = each.value.image_pull_secrets
    container_port        = each.value.container_port
    service_port          = each.value.service_port
    rollout_enabled       = each.value.rollout_enabled
    max_surge             = each.value.max_surge
    max_unavailable       = each.value.max_unavailable
    resource_quota        = each.value.resource_quota
    limit_range           = each.value.limit_range
    rbac                  = each.value.rbac
    cilium_network_policy = each.value.cilium_network_policy
    route_enabled         = each.value.route_enabled
    route_host            = each.value.route_host
    identity              = each.value.identity
    database              = each.value.database
    redis                 = each.value.redis
    kafka                 = each.value.kafka
  })
}
