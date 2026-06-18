output "environment_files" {
  description = "Generated service environment files keyed by environment name."
  value = {
    for env_name, file in local_file.environment : env_name => file.filename
  }
}

output "routes" {
  description = "Generated route hostnames keyed by environment name."
  value = {
    for env_name, env in local.normalized_environments : env_name => env.route_host
  }
}
