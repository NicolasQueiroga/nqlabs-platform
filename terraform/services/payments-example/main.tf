# payments-example — canonical example wiring all cloud-* modules together.
#
# This is an EXAMPLE (not a real service) showing how to compose cloud-iam,
# cloud-secrets, cloud-database, cloud-redis, cloud-kafka, and nqlabs-service
# into a single deployment unit on GCP.
#
# Run:
#   terraform init
#   terraform plan -var-file=staging.tfvars
#   terraform apply -var-file=staging.tfvars
#
# After apply: review git diff in apps/payments-example/environments/, open a PR.

# ---------------------------------------------------------------------------
# 1. Workload Identity (GCP WIF)
# ---------------------------------------------------------------------------

module "iam" {
  source = "../../modules/cloud-iam/gcp"

  project     = var.gcp_project
  environment = var.environment
  service_name = "payments-example"
  namespace    = "payments-example-${var.environment}"

  roles = [
    "roles/cloudsql.client",
    "roles/secretmanager.secretAccessor",
    "roles/redis.viewer",
  ]

  cluster_name      = var.gke_cluster_name
  cluster_location  = var.gcp_region
  create_pool       = false  # pool created once per cluster by the platform team
  workload_identity_pool_id = var.workload_identity_pool_id
}

# ---------------------------------------------------------------------------
# 2. Application secrets (non-infra: API keys, webhook secrets)
# ---------------------------------------------------------------------------

module "secrets" {
  source = "../../modules/cloud-secrets/gcp"

  project               = var.gcp_project
  service_name          = "payments-example"
  environment           = var.environment
  service_account_email = module.iam.service_account_email

  secrets = [
    { name = "stripe-api-key",     description = "Stripe live/test API key" },
    { name = "webhook-signing-secret", description = "Stripe webhook endpoint secret" },
  ]
}

# ---------------------------------------------------------------------------
# 3. Managed PostgreSQL (Cloud SQL)
# ---------------------------------------------------------------------------

module "db" {
  source = "../../modules/cloud-database/gcp"

  project               = var.gcp_project
  region                = var.gcp_region
  service_name          = "payments-example"
  environment           = var.environment
  tier                  = var.environment == "production" ? "standard" : "small"
  deletion_protection   = var.environment == "production"
  service_account_email = module.iam.service_account_email
}

# ---------------------------------------------------------------------------
# 4. Managed Redis (Memorystore)
# ---------------------------------------------------------------------------

module "redis" {
  source = "../../modules/cloud-redis/gcp"

  project               = var.gcp_project
  region                = var.gcp_region
  service_name          = "payments-example"
  environment           = var.environment
  tier                  = var.environment == "production" ? "standard" : "small"
  service_account_email = module.iam.service_account_email
}

# ---------------------------------------------------------------------------
# 5. Kafka topics (Confluent Cloud)
# ---------------------------------------------------------------------------

module "kafka" {
  source = "../../modules/cloud-kafka/confluent"

  service_name           = "payments-example"
  environment            = var.environment
  cloud_provider         = "GCP"
  region                 = var.gcp_region
  tier                   = var.environment == "production" ? "dedicated" : "basic"
  confluent_environment_id = var.confluent_environment_id

  topics = [
    {
      name       = "payments-example.payment-initiated"
      partitions = 6
      config     = { "retention.ms" = "604800000" }
    },
    {
      name       = "payments-example.payment-completed"
      partitions = 6
    },
    {
      name       = "payments-example.payment-failed"
      partitions = 3
    },
  ]
}

# ---------------------------------------------------------------------------
# 6. Environment descriptor (writes apps/payments-example/environments/<env>.yaml)
# ---------------------------------------------------------------------------

module "payments_example" {
  source    = "../../modules/nqlabs-service"
  name      = "payments-example"
  apps_root = "${path.module}/../../../apps"

  environments = {
    (var.environment) = {
      image_repository = "ghcr.io/nqlabs/payments-example"
      image_tag        = var.image_tag

      identity = {
        provider     = "gcp-wif"
        gcp_sa_email = module.iam.service_account_email
      }

      database = {
        enabled = true
        tier    = var.environment == "production" ? "standard" : "small"
      }

      redis = {
        enabled = true
        ha      = var.environment == "production"
      }

      kafka = {
        enabled = true
        topics = [
          { name = "payments-example.payment-initiated", partitions = 6, replicas = 1 },
          { name = "payments-example.payment-completed", partitions = 6, replicas = 1 },
          { name = "payments-example.payment-failed",   partitions = 3, replicas = 1 },
        ]
      }
    }
  }
}
