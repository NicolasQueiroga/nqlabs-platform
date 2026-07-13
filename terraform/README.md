# Terraform

Terraform is the **scaffolder and cloud provisioner** for the NQLabs platform.
It generates GitOps descriptors and provisions managed cloud resources, but never
mutates the Kubernetes cluster directly.

## Operating model

```
terraform apply
  -> local file writes (environment YAMLs, ArgoCD manifests)
  -> cloud resource provisioning (IAM, secrets, databases, caches, queues)
  -> git diff review
  -> pull request
  -> merge
  -> ArgoCD reconciliation
```

Git stays the single source of truth for the Kubernetes control plane.
Terraform owns the cloud periphery.

---

## Module catalogue

### `modules/nqlabs-service`

Generates `apps/<service>/environments/{staging,production}.yaml` consumed by
the service ApplicationSet. Supports identity provider annotation, data layer
flags (database, redis, kafka), and the full rollout/network policy surface.

### `modules/cloud-iam`

Cloud workload identity — pairs with `serviceAccount.identity` in the chart.

| Sub-module | Provider | What it creates |
|---|---|---|
| `cloud-iam/gcp` | Google Cloud | GCP Service Account, IAM role bindings, WIF pool+provider (once per cluster), workloadIdentityUser binding |
| `cloud-iam/aws` | AWS | IRSA IAM Role with OIDC trust policy, policy attachments |
| `cloud-iam/azure` | Azure | User-Assigned Managed Identity, Federated Identity Credential (AKS OIDC), role assignments |

### `modules/cloud-secrets`

Managed secret store + access grant. Creates the store resource only (no
secret values). Pairs with cloud-iam.

| Sub-module | Provider | What it creates |
|---|---|---|
| `cloud-secrets/gcp` | Google Cloud | Secret Manager secrets + secretAccessor IAM binding |
| `cloud-secrets/aws` | AWS | Secrets Manager secrets + IAM policy attached to the IRSA role |
| `cloud-secrets/azure` | Azure | Key Vault + access policy for the Managed Identity |

### `modules/cloud-database`

Managed PostgreSQL. The in-cluster (local) path uses the nqlabs-service Helm
chart with `database.enabled=true` (CloudNativePG). Use these modules when
deploying to a cloud.

| Sub-module | Provider | What it creates |
|---|---|---|
| `cloud-database/gcp` | Google Cloud | Cloud SQL for PostgreSQL 17, connection URL in Secret Manager |
| `cloud-database/aws` | AWS | RDS PostgreSQL 17 (Multi-AZ for standard/large), connection URL in Secrets Manager |
| `cloud-database/azure` | Azure | Azure Database for PostgreSQL Flexible Server 17, connection URL in Key Vault |

Tiers: `small` (single-AZ, minimal resources) | `standard` (HA, mid-size) | `large` (HA, production-grade).

### `modules/cloud-redis`

Managed Redis/Valkey. The in-cluster path uses the chart with `redis.enabled=true`.

| Sub-module | Provider | What it creates |
|---|---|---|
| `cloud-redis/gcp` | Google Cloud | Memorystore Redis 7, auth string in Secret Manager |
| `cloud-redis/aws` | AWS | ElastiCache Redis 7 Replication Group, auth token in Secrets Manager |
| `cloud-redis/azure` | Azure | Azure Cache for Redis 7, connection string in Key Vault |

### `modules/cloud-kafka`

Managed Kafka. The in-cluster path uses Strimzi/Kafka (Redpanda removed) (chart with `kafka.enabled=true`).

| Sub-module | Provider | What it creates |
|---|---|---|
| `cloud-kafka/confluent` | Confluent Cloud | Environment, Kafka cluster, service account, ACLs, API key, topics |
| `cloud-kafka/msk` | AWS | MSK Kafka 3.x cluster, SASL/SCRAM credentials in Secrets Manager |
| `cloud-kafka/event-hubs` | Azure | Event Hubs namespace (Kafka-compatible), Event Hubs (topics), auth rule |

---

## Composition example — GCP service with full cloud stack

```hcl
# terraform/services/payments/main.tf

# 1. Workload identity
module "iam" {
  source      = "../../modules/cloud-iam/gcp"
  project     = var.gcp_project
  service_name = "payments"
  environment = "production"
  namespace   = "payments-production"
  roles       = ["roles/cloudsql.client", "roles/secretmanager.secretAccessor"]
  cluster_name     = "nqlabs-production"
  cluster_location = "us-central1"
  create_pool      = false  # created once by the platform team
  workload_identity_pool_id = "nqlabs-production-pool"
}

# 2. Secret store
module "secrets" {
  source                = "../../modules/cloud-secrets/gcp"
  project               = var.gcp_project
  service_name          = "payments"
  environment           = "production"
  service_account_email = module.iam.service_account_email
  secrets = [
    { name = "stripe-key" },
    { name = "webhook-secret" },
  ]
}

# 3. Managed PostgreSQL
module "db" {
  source                = "../../modules/cloud-database/gcp"
  project               = var.gcp_project
  region                = "us-central1"
  service_name          = "payments"
  environment           = "production"
  tier                  = "standard"
  service_account_email = module.iam.service_account_email
}

# 4. Managed Redis
module "redis" {
  source                = "../../modules/cloud-redis/gcp"
  project               = var.gcp_project
  region                = "us-central1"
  service_name          = "payments"
  environment           = "production"
  tier                  = "standard"
  service_account_email = module.iam.service_account_email
}

# 5. Environment descriptor (writes apps/payments/environments/production.yaml)
module "payments" {
  source    = "../../modules/nqlabs-service"
  name      = "payments"
  apps_root = "${path.module}/../../../apps"

  environments = {
    production = {
      image_repository = "ghcr.io/nqlabs/payments"
      image_tag        = "v1.2.3"
      identity = {
        provider     = "gcp-wif"
        gcp_sa_email = module.iam.service_account_email
      }
      database = { enabled = true, tier = "standard" }
      redis    = { enabled = true, ha = true }
    }
  }
}
```

---

## State management

Local state is `.gitignore`d. Provider lock files (`.terraform.lock.hcl`)
are committed so runs are reproducible.

For shared / team-operated use, add a remote state backend (GCS bucket,
S3 bucket, or Terraform Cloud workspace) per service in `services/<name>/backend.tf`.

## Adding a new cloud service

1. `mkdir terraform/services/<name>`
2. Call the modules you need (see example above)
3. `terraform init && terraform plan`
4. Review the generated `apps/<name>/environments/*.yaml` diffs
5. Open a PR — ArgoCD reconciles after merge
