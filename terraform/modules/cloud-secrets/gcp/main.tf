locals {
  # Normalise the secrets list into a map keyed by secret name for for_each.
  secrets_map = {
    for s in var.secrets : s.name => s
  }
}

# One Secret Manager secret resource per entry. No version/value is set here;
# values are added out-of-band (CI, manual, or a separate secrets-seed process).
resource "google_secret_manager_secret" "this" {
  for_each = local.secrets_map

  project   = var.project
  secret_id = "${var.service_name}__${var.environment}__${each.key}"

  labels = {
    service     = var.service_name
    environment = var.environment
  }

  replication {
    auto {}
  }
}

# Grant secretAccessor to the workload identity service account so the running
# pod (via cloud-iam WIF binding) can fetch secret values at runtime.
resource "google_secret_manager_secret_iam_member" "accessor" {
  for_each = local.secrets_map

  project   = var.project
  secret_id = google_secret_manager_secret.this[each.key].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.service_account_email}"
}
