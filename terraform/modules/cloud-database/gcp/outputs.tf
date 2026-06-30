output "instance_name" {
  description = "Cloud SQL instance name."
  value       = google_sql_database_instance.main.name
}

output "connection_name" {
  description = "Cloud SQL connection name (project:region:instance) used by the Cloud SQL Auth Proxy."
  value       = google_sql_database_instance.main.connection_name
}

output "database_name" {
  description = "PostgreSQL database name created for the service."
  value       = google_sql_database.main.name
}

output "secret_id" {
  description = "Secret Manager secret ID storing the connection details (username, password, connection_url)."
  value       = google_secret_manager_secret.connection.secret_id
}

output "secret_name" {
  description = "Full Secret Manager resource name."
  value       = google_secret_manager_secret.connection.name
}
