locals {
  name = "${var.service_name}-${var.environment}"

  tier_map = {
    small    = "db-f1-micro"
    standard = "db-n1-standard-2"
    large    = "db-n1-standard-4"
  }

  availability_map = {
    small    = "ZONAL"
    standard = "REGIONAL"
    large    = "REGIONAL"
  }

  instance_tier        = local.tier_map[var.tier]
  availability_type    = local.availability_map[var.tier]
  database_name        = replace(var.service_name, "-", "_")
  db_user              = replace(var.service_name, "-", "_")
  secret_id_connection = "${var.service_name}/${var.environment}/database"
}

resource "random_password" "db" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "google_sql_database_instance" "main" {
  project          = var.project
  name             = local.name
  region           = var.region
  database_version = "POSTGRES_17"

  deletion_protection = var.deletion_protection

  settings {
    tier              = local.instance_tier
    availability_type = local.availability_type
    disk_autoresize   = true
    disk_size         = 10

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7
      backup_retention_settings {
        retained_backups = 7
        retention_unit   = "COUNT"
      }
    }

    database_flags {
      name  = "max_connections"
      value = "100"
    }

    insights_config {
      query_insights_enabled = true
    }
  }
}

resource "google_sql_database" "main" {
  project  = var.project
  name     = local.database_name
  instance = google_sql_database_instance.main.name
}

resource "google_sql_user" "main" {
  project  = var.project
  name     = local.db_user
  instance = google_sql_database_instance.main.name
  password = random_password.db.result
}

# Store the connection details in Secret Manager so the platform ESO ClusterSecretStore
# and application pods can retrieve the DATABASE_URL without embedding credentials in git.
resource "google_secret_manager_secret" "connection" {
  project   = var.project
  secret_id = replace(local.secret_id_connection, "/", "__")

  labels = {
    service     = var.service_name
    environment = var.environment
    managed_by  = "terraform"
  }

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "connection" {
  secret = google_secret_manager_secret.connection.id

  secret_data = jsonencode({
    username       = local.db_user
    password       = random_password.db.result
    host           = google_sql_database_instance.main.private_ip_address
    database       = local.database_name
    connection_url = "postgresql://${local.db_user}:${random_password.db.result}@${google_sql_database_instance.main.private_ip_address}:5432/${local.database_name}"
  })
}

# Grant the service's GCP service account permission to read the secret.
resource "google_secret_manager_secret_iam_member" "connection_accessor" {
  project   = var.project
  secret_id = google_secret_manager_secret.connection.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.service_account_email}"
}
