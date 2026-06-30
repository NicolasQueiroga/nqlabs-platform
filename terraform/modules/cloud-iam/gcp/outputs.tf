output "service_account_email" {
  description = "Email of the created GCP service account. Set as the iam.gke.io/gcp-service-account annotation on the Kubernetes ServiceAccount."
  value       = google_service_account.this.email
}

output "workload_identity_pool_id" {
  description = "Workload Identity pool ID. Pass this as workload_identity_pool_id to sibling service modules in the same cluster."
  value       = local.pool_id
}

output "workload_identity_provider_id" {
  description = "Full resource name of the Workload Identity pool provider."
  value       = var.create_pool ? google_iam_workload_identity_pool_provider.cluster[0].name : ""
}
