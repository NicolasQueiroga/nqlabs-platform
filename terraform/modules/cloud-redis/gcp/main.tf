locals {
  memory_size_gb = var.tier == "standard" ? 2 : 1
  redis_tier     = var.tier == "standard" ? "STANDARD_HA" : "BASIC"
  instance_name  = "${var.service_name}-${var.environment}"
  secret_name    = "${var.service_name}/${var.environment}/redis"
}

resource "google_redis_instance" "this" {
  project            = var.project
  region             = var.region
  name               = local.instance_name
  tier               = local.redis_tier
  memory_size_gb     = local.memory_size_gb
  redis_version      = "REDIS_7_0"
  auth_enabled       = true
  authorized_network = var.authorized_network != "" ? var.authorized_network : null

  transit_encryption_mode = "SERVER_AUTHENTICATION"

  labels = {
    service     = var.service_name
    environment = var.environment
    managed-by  = "terraform"
  }
}

# Store connection info as a secret so the service can consume it via ESO.
resource "google_secret_manager_secret" "redis" {
  project   = var.project
  secret_id = replace(local.secret_name, "/", "__")

  replication {
    auto {}
  }

  labels = {
    service     = var.service_name
    environment = var.environment
  }
}

resource "google_secret_manager_secret_version" "redis" {
  secret = google_secret_manager_secret.redis.id

  secret_data = jsonencode({
    host      = google_redis_instance.this.host
    port      = tostring(google_redis_instance.this.port)
    auth_string = google_redis_instance.this.auth_string
    redis_url = "rediss://:${google_redis_instance.this.auth_string}@${google_redis_instance.this.host}:${google_redis_instance.this.port}"
  })
}

# Grant the service identity read access to the connection secret.
resource "google_secret_manager_secret_iam_member" "redis_accessor" {
  project   = var.project
  secret_id = google_secret_manager_secret.redis.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.service_account_email}"
}
