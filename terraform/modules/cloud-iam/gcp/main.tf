locals {
  k8s_sa_name = coalesce(var.k8s_sa_name, var.service_name)

  # Effective pool ID — either newly created or caller-supplied.
  pool_id = var.create_pool ? google_iam_workload_identity_pool.cluster[0].workload_identity_pool_id : var.workload_identity_pool_id

  # Workload Identity member string used by GKE to impersonate the GCP SA.
  wi_member = "serviceAccount:${var.project}.svc.id.goog[${var.namespace}/${local.k8s_sa_name}]"

  common_labels = {
    managed-by  = "terraform"
    service     = var.service_name
    environment = var.environment
  }
}

# --- Service Account -----------------------------------------------------------

resource "google_service_account" "this" {
  project      = var.project
  account_id   = var.service_name
  display_name = "${var.service_name} (${var.environment})"
  description  = "Workload identity SA for ${var.service_name} in ${var.environment}."
}

# --- IAM role bindings --------------------------------------------------------

resource "google_project_iam_member" "roles" {
  for_each = toset(var.roles)

  project = var.project
  role    = each.value
  member  = "serviceAccount:${google_service_account.this.email}"
}

# --- Workload Identity pool + provider (once per cluster) ---------------------

resource "google_iam_workload_identity_pool" "cluster" {
  count = var.create_pool ? 1 : 0

  project                   = var.project
  workload_identity_pool_id = "${var.cluster_name}-pool"
  display_name              = "GKE ${var.cluster_name}"
  description               = "Workload Identity pool for GKE cluster ${var.cluster_name}."
}

resource "google_iam_workload_identity_pool_provider" "cluster" {
  count = var.create_pool ? 1 : 0

  project                            = var.project
  workload_identity_pool_id          = google_iam_workload_identity_pool.cluster[0].workload_identity_pool_id
  workload_identity_pool_provider_id = "${var.cluster_name}-provider"
  display_name                       = "GKE ${var.cluster_name} OIDC"

  oidc {
    # GKE issues tokens from this URL; GCP validates them against the cluster's
    # JWKS endpoint automatically when the pool provider is created.
    issuer_uri = "https://container.googleapis.com/v1/projects/${var.project}/locations/${var.cluster_location}/clusters/${var.cluster_name}"
  }

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.namespace"  = "assertion['kubernetes.io']['namespace']"
    "attribute.sa_name"    = "assertion['kubernetes.io']['serviceaccount']['name']"
  }
}

# --- Workload Identity binding ------------------------------------------------

resource "google_service_account_iam_member" "wi_binding" {
  service_account_id = google_service_account.this.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project}.svc.id.goog[${var.namespace}/${local.k8s_sa_name}]"
}
