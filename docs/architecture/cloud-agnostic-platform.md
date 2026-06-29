# NQLabs Cloud-Agnostic Platform — Architecture Blueprint

> **Status:** Planning. This document maps the NQLabs platform to a cloud-agnostic
> service factory model inspired by a reference enterprise architecture (GCP-based),
> identifies the gaps, and proposes a phased implementation plan. No code changes
> yet — this is the blueprint.

---

## 1. Context and Goals

### What we're solving

The NQLabs home-lab platform has matured into a multi-cluster Kubernetes system
with GitOps, identity, monitoring, and a service factory. A reference enterprise
architecture (documented in `platform-repos-and-new-service-guide.md`) shows how a
production platform team manages 400+ services across GCP with a structured,
multi-repo, highly automated approach.

The goal is to:

1. **Mimic the enterprise process** — structured service creation, declarative
   descriptors, automated CI/CD, progressive delivery.
2. **Make it cloud-agnostic** — the service descriptors and chart should work
   on local (Talos), GCP, AWS, or Azure with minimal adjustments.
3. **Prefer open-source for local** — but commercial/cloud-native tools are
   acceptable when justifiable (e.g., cloud-managed databases, secret managers).

### Design principles

- **The service descriptor is the contract.** `app.yaml` + `environments/*.yaml`
  declare *what* a service is and *where* it runs. The chart and Terraform handle
  *how* it's provisioned per cloud.
- **ESO is the secrets abstraction.** External Secrets Operator already supports
  OpenBao, Infisical, GCP Secret Manager, AWS Secrets Manager, Azure Key Vault,
  and 1Password. The service descriptor just changes the store name.
- **K8s is the portable layer.** Everything that runs in Kubernetes (workloads,
  networking, policies, monitoring) is the same across clouds. Only the
  cloud-managed infrastructure (databases, IAM, secret stores, networking)
  changes per cloud, and that's handled by Terraform.
- **Local first, cloud second.** The local platform is the primary development
  environment. Cloud deployments are a deployment target, not a rewrite.

---

## 2. Current State Assessment

### What's already built (and working)

| Capability | Implementation | Status |
|---|---|---|
| Shared Helm chart | `charts/nqlabs-service` — renders Deployment/Rollout, HPA, PDB, Service, HTTPRoute, ExternalSecret, ServiceMonitor, CiliumNetworkPolicy, RBAC, ConfigMap, multi-workload, preview, canary with traffic routing + analysis | ✅ |
| Service identity | `apps/<service>/app.yaml` — metadata, exposure, dependencies, default shape | ✅ |
| Per-env runtime | `apps/<service>/environments/{staging,production}.yaml` — image, namespace, cluster, route, canary | ✅ |
| Service scaffolding | `.github/workflows/app-create.yaml` — generates descriptors, opens PR | ✅ |
| Supply chain hardening | `.github/workflows/image-supply-chain-reusable.yaml` — Trivy + Cosign + SBOM | ✅ |
| Preview environments | `.github/workflows/preview-reusable.yaml` — `/preview deploy\|renew\|destroy\|status` | ✅ |
| Multi-cluster GitOps | ArgoCD ApplicationSet watches `apps/*/environments/*.yaml`, deploys by cluster name | ✅ |
| Progressive delivery | Argo Rollouts with canary, Gateway API traffic routing, analysis templates | ✅ |
| Terraform service module | `terraform/modules/nqlabs-service` — generates env YAML files | ⚠️ Partial |
| Platform infrastructure | `infrastructure/` — Authentik, Cilium, Rook/Ceph, monitoring, cert-manager, ESO, OpenBao | ✅ |
| Cluster config | `clusters/` — management, staging, production | ✅ |

### What's missing

| Gap | Impact | Priority |
|---|---|---|
| Secrets provider abstraction | Store name hardcoded to `nqlabs-openbao`; no cloud-native secret manager support | High |
| CI/CD deploy automation | No `github-builder` equivalent; image tags updated manually | High |
| Cloud IaC modules | No Terraform modules for GCP/AWS/Azure infrastructure | Medium (needed for cloud) |
| Database provisioning per service | No automated CloudNativePG/RDS/CloudSQL provisioning per service | Medium |
| Identity provider abstraction | No GCP WIF / AWS IRSA / Azure MI binding in the chart | Medium (needed for cloud) |

---

## 3. Reference Architecture (Enterprise GCP)

The reference enterprise architecture uses 4 repositories:

| Repo | Role | NQLabs equivalent |
|---|---|---|
| `terraform` | GCP cloud infrastructure (GKE, VPCs, IAM, Secret Manager, WIF) | `terraform/` (minimal) |
| `terraform-data` | Per-service data infrastructure (CloudSQL, PgBouncer, Kafka) | `terraform/services/` (minimal) |
| `monorepo-gitops` | Kubernetes desired state for 400+ services | `apps/` + `charts/` |
| `resources-provisioning` | Cluster-level platform resources | `infrastructure/` + `clusters/` + `platform/` |

### Enterprise service creation flow (10 steps)

```
[1] terraform        → GCP Service Account + IAM roles
[2] terraform        → GCP Secret Manager entry
[3] terraform        → GitHub Actions WIF Service Account
[4] terraform-data   → CloudSQL instance
[5] terraform-data   → PgBouncer configuration
[6] terraform        → Redis/Memorystore (if needed)
[7] terraform-data   → Kafka topics/CDC (if needed)
[8] monorepo-gitops  → Chart.yaml + staging.yaml + production.yaml
[9] monorepo-gitops  → Register in helms/argocd/values.yaml
[10] app repo        → Configure github-builder CI workflow
```

### NQLabs service creation flow (current)

```
[1] platform repo    → Run app-create.yaml workflow (generates app.yaml + envs)
[2] platform repo    → Merge PR (ArgoCD ApplicationSet auto-detects)
[3] app repo         → Add caller workflows (build, deploy, preview)
[4] app repo         → Merge to main → CI builds → pushes to GHCR → updates staging.yaml
[5] ArgoCD           → Detects change → deploys to staging cluster
[6] app repo         → Release tag → CI updates production.yaml
[7] ArgoCD           → Deploys to production via Argo Rollouts canary
```

### NQLabs service creation flow (target, cloud-agnostic)

```
[1] platform repo    → Run app-create.yaml workflow (generates app.yaml + envs)
[2] terraform        → (cloud only) Provision IAM, secrets backend, database, redis
[3] platform repo    → Merge PR (ArgoCD ApplicationSet auto-detects)
[4] app repo         → Add caller workflows (build, deploy, preview)
[5] app repo         → Merge to main → CI builds → pushes to registry → updates staging.yaml
[6] ArgoCD           → Detects change → deploys to staging cluster
[7] app repo         → Release tag → CI updates production.yaml
[8] ArgoCD           → Deploys to production via Argo Rollouts canary
```

The key difference: step 2 (Terraform) is only needed for cloud deployments. Locally,
Kubernetes handles everything (CloudNativePG for databases, K8s SAs for identity,
Infisical/OpenBao for secrets).

---

## 4. Gap Analysis

### Gap 1: Secrets Provider Abstraction

**Current state:**

The chart accepts `externalSecrets.store` (default: `nqlabs-openbao`), but the
`ClusterSecretStore` is a platform-level resource hardcoded to OpenBao. The store
name is not a function of the environment or cloud provider.

**Target state:**

Each cluster/environment has its own `ClusterSecretStore` pointing to the
appropriate backend. The service descriptor just references the store by name.

| Cloud | Secret backend | ESO provider | Store name |
|---|---|---|---|
| Local | Infisical (recommended) or OpenBao | `infisical` or `vault` | `nqlabs-infisical` or `nqlabs-openbao` |
| GCP | GCP Secret Manager | `gcpsm` | `gcp-secret-manager` |
| AWS | AWS Secrets Manager | `awssm` | `aws-secrets-manager` |
| Azure | Azure Key Vault | `azurekv` | `azure-key-vault` |

**What needs to change:**

1. **Platform level:** Each cluster defines its own `ClusterSecretStore` in
   `clusters/<cluster>/external-secrets/` pointing to the right backend.
   (Partially done — staging and production already have their own ESO config.)
2. **Chart level:** No change needed — the chart already accepts any store name.
3. **Service descriptor:** The `externalSecrets.store` field in environment YAMLs
   uses the cluster's store name. This is already configurable.
4. **Local backend:** Switch from OpenBao to Infisical (see Section 7).

**Effort:** Low. The chart already supports this. The main work is deploying
Infisical and creating a new ClusterSecretStore.

### Gap 2: CI/CD Deploy Automation

**Current state:**

The platform has supply chain hardening (Trivy scan, Cosign signing, SBOM
attestation) and preview environment automation. But there's no automated
deploy workflow — image tags in `apps/<service>/environments/*.yaml` are
updated manually.

The reference enterprise architecture has `github-builder`, a tool that:
1. Authenticates to the cloud (GCP WIF)
2. Builds and pushes container image
3. Updates the version field in the GitOps repo
4. Triggers ArgoCD sync (staging only; production auto-detects)

**Target state:**

A reusable workflow (`deploy-reusable.yaml`) in the platform repo that app
repos call after build/push:

```
App repo workflow:
  1. Build container image
  2. Push to registry (GHCR for local, GCR/ECR/ACR for cloud)
  3. Call image-supply-chain-reusable.yaml (scan, sign, SBOM)
  4. Call deploy-reusable.yaml with:
     - service name
     - environment (staging | production)
     - image tag (SHA or version)
     - platform repo token
  5. deploy-reusable.yaml:
     a. Checkout platform repo
     b. Update image.tag in apps/<service>/environments/<env>.yaml
     c. Commit and push
     d. (staging only) Call ArgoCD API to force sync
     e. (production) Just update GitOps — ArgoCD auto-detects
```

**Registry abstraction:**

| Cloud | Registry | Auth |
|---|---|---|
| Local | GHCR (ghcr.io) | GitHub OIDC |
| GCP | GCR / Artifact Registry | GCP WIF |
| AWS | ECR | AWS OIDC |
| Azure | ACR | Azure OIDC |

The app repo's build workflow pushes to the appropriate registry based on the
target environment. The image repository is already in the environment YAML
(`image.repository`), so this is already abstracted.

**Effort:** Medium. One reusable workflow + app repo workflow templates.

### Gap 3: Cloud IaC Modules

**Current state:**

The `terraform/` directory has:
- `modules/nqlabs-service/` — generates env YAML files (Terraform → local_file)
- `services/demo/` — demo service using the module

No cloud infrastructure modules exist (no GCP/AWS/Azure resources).

**Target state:**

Multi-cloud Terraform modules that provision cloud-specific infrastructure per
service. The module design uses a `cloud` variable to switch between providers.

```
terraform/
├── modules/
│   ├── nqlabs-service/              # Existing: generates env YAML
│   ├── cloud-iam/                   # NEW: IAM per cloud
│   │   ├── main.tf                  #   provider switch
│   │   ├── gcp.tf                   #   GCP SA + WIF binding
│   │   ├── aws.tf                   #   IAM Role + IRSA trust policy
│   │   ├── azure.tf                 #   Managed Identity + federated credential
│   │   └── local.tf                 #   No-op (K8s SA handles it)
│   ├── cloud-database/              # NEW: Database per cloud
│   │   ├── main.tf
│   │   ├── gcp.tf                   #   CloudSQL instance
│   │   ├── aws.tf                   #   RDS instance
│   │   ├── azure.tf                 #   Azure Database for PostgreSQL
│   │   └── local.tf                 #   CloudNativePG Cluster manifest
│   ├── cloud-secrets/               # NEW: Secret store per cloud
│   │   ├── main.tf
│   │   ├── gcp.tf                   #   GCP Secret Manager secret
│   │   ├── aws.tf                   #   AWS Secrets Manager secret
│   │   ├── azure.tf                 #   Azure Key Vault secret
│   │   └── local.tf                 #   No-op (Infisical/OpenBao in K8s)
│   └── cloud-redis/                 # NEW: Redis per cloud
│       ├── main.tf
│       ├── gcp.tf                   #   Memorystore instance
│       ├── aws.tf                   #   ElastiCache instance
│       ├── azure.tf                 #   Azure Cache for Redis
│       └── local.tf                 #   Valkey StatefulSet manifest
└── services/
    └── <service>/
        └── main.tf                  # Calls modules with cloud config
```

**Module interface:**

```hcl
module "nqlabs_service" {
  source = "../modules/cloud-iam"
  name   = "payments-api"

  cloud = {
    provider = "gcp"           # local | gcp | aws | azure
    region   = "us-east4"
    project  = "nqlabs-production"
  }

  k8s_service_accounts = [
    "payments-api-production/payments-api",
    "payments-api-production/payments-worker",
  ]
}
```

**Effort:** High, but only needed when deploying to a cloud. Can be built
incrementally — start with `local` (no-op), add `gcp` first (since the
reference architecture is GCP-based), then `aws` and `azure`.

### Gap 4: Database Provisioning Per Service

**Current state:**

CloudNativePG is running in the management cluster (for platform services like
Authentik). There's no per-service database provisioning automation — each
service that needs a database would need manual CloudNativePG Cluster creation.

The reference enterprise architecture uses Terraform to provision CloudSQL
instances per service, with PgBouncer as a connection pooler.

**Target state:**

A Terraform module (or K8s manifest generator) that provisions a database per
service:

| Cloud | Database | Connection pooling |
|---|---|---|
| Local | CloudNativePG Cluster in K8s | CNPG Pooler (PgBouncer, managed by CNPG) |
| GCP | CloudSQL (HA, regional) | PgBouncer (in K8s) |
| AWS | RDS (Multi-AZ) | RDS Proxy |
| Azure | Azure Database for PostgreSQL (Flexible Server) | PgBouncer (in K8s) |

**Implementation:**

The `cloud-database` Terraform module generates the manifests and writes them
to the service's directory in the platform repo:

```
terraform/teams/<team>/<service>/
  main.tf                           # Calls cloud-database module
  generated/
    database.yaml                   # CloudNativePG Cluster manifest
    pooler.yaml                     # CNPG Pooler (PgBouncer) manifest
```

CloudNativePG has a built-in `Pooler` CRD that manages PgBouncer instances —
no separate PgBouncer deployment needed. The module generates both the
`Cluster` (primary + replicas) and `Pooler` (connection pooling) manifests.

### Gap 4b: Redis / Caching

**Current state:** No Redis/Valkey provisioning per service.

**Target state:**

| Cloud | Redis |
|---|---|
| Local | Valkey StatefulSet in K8s (open-source Redis fork) |
| GCP | Memorystore |
| AWS | ElastiCache |
| Azure | Azure Cache for Redis |

The `cloud-redis` Terraform module generates the appropriate resource per cloud.
For local, this is a Valkey StatefulSet with persistent storage.

### Gap 4c: Kafka / Event Streaming

**Current state:** No Kafka/event streaming infrastructure.

**Target state:**

| Cloud | Kafka | CDC |
|---|---|---|
| Local | Redpanda in K8s (Kafka-compatible, no ZooKeeper) | Debezium + Redpanda |
| GCP | Confluent Cloud | Debezium + Confluent |
| AWS | MSK | Debezium + MSK |
| Azure | Event Hubs (Kafka-compatible) | Debezium + Event Hubs |

The `cloud-kafka` Terraform module provisions:
- Kafka topics for async messaging/queues between services
- Optional Debezium CDC source (captures DB changes → Kafka topics)
- Optional sink connectors (e.g., BigQuery sink for analytics)

For local, Redpanda is preferred over Strimzi+Kafka because it's a single
binary with no ZooKeeper dependency, simpler to operate, and Kafka-compatible.

**Effort:** Medium-High. Database + PgBouncer is straightforward with CNPG.
Redis and Kafka require deploying and operating the infrastructure first.

### Gap 5: Identity Provider Abstraction

**Current state:**

The chart creates a K8s ServiceAccount with optional annotations. There's no
cloud identity binding (GCP WIF, AWS IRSA, Azure MI).

The reference enterprise architecture binds K8s SAs to GCP SAs via Workload
Identity Federation:
```yaml
serviceAccount:
  identity: payments-api@acme-production.iam.gserviceaccount.com
```

**Target state:**

The chart renders the right SA annotations based on the cloud provider:

```yaml
# In environment YAML:
serviceAccount:
  create: true
  identity:
    provider: none              # local: just a K8s SA
    # provider: gcp-wif         # GCP: annotate with WIF SA email
    # provider: aws-irsa        # AWS: annotate with IAM role ARN
    # provider: azure-mi        # Azure: annotate with Managed Identity
    gcpSA: ""                   # GCP SA email (if gcp-wif)
    awsRoleARN: ""              # AWS IAM role ARN (if aws-irsa)
    azureClientID: ""            # Azure MI client ID (if azure-mi)
    azureTenantID: ""            # Azure tenant ID (if azure-mi)
```

**Chart rendering per provider:**

| Provider | Annotation |
|---|---|
| `none` | (none) |
| `gcp-wif` | `iam.gke.io/gcp-service-account: <gcpSA>` |
| `aws-irsa` | `eks.amazonaws.com/role-arn: <awsRoleARN>` |
| `azure-mi` | `azure.workload.identity/client-id: <azureClientID>` + tenant label |

**Effort:** Low. Small change to the chart's `serviceaccount.yaml` template.

---

## 5. Provider Abstraction Design

The core abstraction is a `provider` block in the environment YAML that
controls all cloud-specific behavior:

```yaml
# apps/payments-api/environments/production.yaml

app:
  name: payments-api

environment:
  name: production
  namespace: payments-api

# --- Cloud provider configuration ---
provider:
  cloud: local                    # local | gcp | aws | azure
  region: ""                      # cloud-specific region (empty for local)

  secrets:
    store: nqlabs-infisical       # ClusterSecretStore name
    # On GCP:  gcp-secret-manager
    # On AWS:  aws-secrets-manager
    # On Azure: azure-key-vault

  identity:
    type: none                    # none | gcp-wif | aws-irsa | azure-mi
    gcpSA: ""
    awsRoleARN: ""
    azureClientID: ""
    azureTenantID: ""

  registry:
    url: ghcr.io                  # GHCR | GCR | ECR | ACR

# --- Service runtime (same for all clouds) ---
image:
  repository: ghcr.io/nicolasqueiroga/payments-api
  tag: sha-abc123

argocd:
  project: services-production
  valueFile: apps/payments-api/environments/production.yaml
  destination:
    name: nqlabs-production

# ... rest of the service config ...
```

### What changes per cloud vs what stays the same

**Stays the same (cloud-agnostic):**
- `app.yaml` — service identity, exposure, dependencies, default shape
- `charts/nqlabs-service` — the Helm chart (renders different resources based on `provider`)
- `infrastructure/` — K8s platform components (Cilium, Authentik, monitoring, etc.)
- `platform/argocd/` — ArgoCD app-of-apps
- `.github/workflows/app-create.yaml` — service scaffolding
- `.github/workflows/preview-reusable.yaml` — preview environments
- `.github/workflows/image-supply-chain-reusable.yaml` — supply chain hardening

**Changes per cloud:**
- `provider` block in environment YAMLs
- `terraform/` — cloud-specific infrastructure modules
- `externalSecrets.store` — points to the cluster's ClusterSecretStore
- `serviceAccount.identity` — cloud identity binding
- `image.repository` — registry URL prefix
- Cluster networking (VPC/VNet, subnets, firewalls — handled by Terraform)

---

## 6. Secrets Management Strategy

### Decision: ESO as abstraction layer, Infisical as local backend

**Rationale:**

ESO is already running and already in the service chart. It supports all major
secret backends. The service descriptor just changes the store name per
environment. This is the lowest-friction path to cloud-agnosticism.

For the local backend, Infisical is recommended over OpenBao:

| Criterion | OpenBao (current) | Infisical (proposed) |
|---|---|---|
| OIDC with Authentik | API calls to configure discovery URL, scopes, claims, roles | Configured in web UI |
| Operational model | Raft cluster, unsealing ceremony, leader election | PostgreSQL + Redis, no unsealing |
| Storage backend | Raft (PVCs, manual backup) | PostgreSQL (CloudNativePG, already running) |
| State loss risk | Lost all state on cluster re-init (happened this session) | PostgreSQL is persistent and backed up |
| Web UI | Basic | Modern, polished |
| Kubernetes integration | ESO (Vault provider) | ESO (Infisical provider) + native K8s Operator |
| Secret scoping | Manual path-based (kv/data/...) | Built-in environment-based (dev/staging/prod) |
| Push secrets (K8s → store) | Not supported via ESO | InfisicalPushSecret CRD |
| License | MPL-2.0 | MIT |
| PKI engine | Yes (already bootstrapped for cert-manager) | Machine Identity (newer) |

**What we keep OpenBao for:**

The PKI engine is already bootstrapped and working with cert-manager. There's
no urgent need to migrate it. The ClusterIssuer (`nqlabs-openbao-pki`) signs
certificates via `pki/sign/cert-manager`. This can stay as-is.

### Migration path (OpenBao → Infisical)

1. Deploy Infisical (Helm chart, CloudNativePG backend)
2. Configure OIDC SSO with Authentik (in Infisical web UI)
3. Create Machine Identity with Kubernetes Auth
4. Create `ClusterSecretStore` (`nqlabs-infisical`) pointing to Infisical
5. Migrate secrets from OpenBao KV to Infisical (via CLI or API)
6. Update environment YAMLs: `externalSecrets.store: nqlabs-infisical`
7. Verify all ExternalSecrets sync
8. Decommission OpenBao KV engine (keep PKI engine for cert-manager)

### Cloud secrets strategy

| Cloud | Backend | Why |
|---|---|---|
| Local | Infisical (self-hosted) | Open-source, easy OIDC, PostgreSQL backend |
| GCP | GCP Secret Manager | Native, managed, no ops, cheap |
| AWS | AWS Secrets Manager | Native, managed, no ops |
| Azure | Azure Key Vault | Native, managed, no ops |

On cloud, there's no need to run Infisical or OpenBao — the cloud provider's
native secret manager is cheaper, more reliable, and requires no ops. ESO
supports all of them. The service descriptor just changes the store name.

---

## 7. CI/CD Pipeline Design

### Current flow

```
App repo PR         → build/test only (+ optional /preview deploy)
App repo main merge → CI builds image, pushes to GHCR
                      (manual: update staging.yaml image tag)
                      ArgoCD detects change → deploys to staging
App repo release    → (manual: update production.yaml image tag)
                      ArgoCD deploys to production via canary
```

### Target flow

```
App repo PR         → build/test only (+ optional /preview deploy)
App repo main merge → CI builds image, pushes to GHCR
                      CI calls deploy-reusable.yaml:
                        → updates staging.yaml image.tag
                        → commits to platform repo
                        → calls ArgoCD API to force sync (staging)
                      ArgoCD deploys to staging
App repo release    → CI calls deploy-reusable.yaml:
                        → updates production.yaml image.tag
                        → commits to platform repo
                        (no force sync — ArgoCD auto-detects)
                      ArgoCD deploys to production via canary
```

### Workflow structure

```
Platform repo (.github/workflows/):
  app-create.yaml                    # Service scaffolding (exists)
  image-supply-chain-reusable.yaml   # Scan + sign + SBOM (exists)
  preview-reusable.yaml              # Preview environments (exists)
  preview-reaper-reusable.yaml       # Preview cleanup (exists)
  deploy-reusable.yaml               # NEW: update GitOps + trigger sync
  validate.yaml                      # CI validation (exists)

App repo (.github/workflows/):
  build.yaml                         # Build + push + call supply chain
  deploy-staging.yaml                # Call deploy-reusable for staging
  deploy-production.yaml             # Call deploy-reusable for production
  preview.yaml                       # Call preview-reusable (exists)
```

### `deploy-reusable.yaml` interface

```yaml
name: Deploy (reusable)

on:
  workflow_call:
    inputs:
      service:
        description: Service name (apps/<service>/)
        required: true
        type: string
      environment:
        description: Target environment (staging | production)
        required: true
        type: string
      image-tag:
        description: Image tag to deploy (SHA or version)
        required: true
        type: string
    secrets:
      PLATFORM_REPO_TOKEN:
        required: true
      ARGOCD_STAGING_TOKEN:
        required: false
      ARGOCD_PRODUCTION_TOKEN:
        required: false

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          repository: NicolasQueiroga/nqlabs-platform
          token: ${{ secrets.PLATFORM_REPO_TOKEN }}

      - name: Update image tag
        run: |
          yq -i '.image.tag = "${{ inputs.image-tag }}"' \
            "apps/${{ inputs.service }}/environments/${{ inputs.environment }}.yaml"

      - name: Commit and push
        run: |
          git config user.name 'github-actions[bot]'
          git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
          git add "apps/${{ inputs.service }}/environments/${{ inputs.environment }}.yaml"
          git commit -m "deploy(${{ inputs.service }}): ${{ inputs.environment }} → ${{ inputs.image-tag }}"
          git push

      - name: Trigger ArgoCD sync (staging only)
        if: inputs.environment == 'staging'
        run: |
          # Call ArgoCD API to force sync
          # Production: no force sync — ArgoCD auto-detects, Rollouts controls canary
```

### Cloud-agnostic registry

The app repo's build workflow pushes to the appropriate registry based on the
target environment. The registry URL is already in the environment YAML
(`image.repository`), so the build workflow just reads it.

| Cloud | Registry | Build auth |
|---|---|---|
| Local | GHCR (ghcr.io) | GitHub OIDC (GITHUB_TOKEN) |
| GCP | Artifact Registry | GCP WIF (GitHub OIDC → GCP SA) |
| AWS | ECR | AWS OIDC (GitHub OIDC → IAM Role) |
| Azure | ACR | Azure OIDC (GitHub OIDC → Managed Identity) |

---

## 8. Terraform Module Design

### Module structure

```
terraform/
├── modules/
│   ├── nqlabs-service/              # Existing: generates env YAML
│   ├── cloud-iam/                   # NEW: IAM per cloud
│   ├── cloud-database/              # NEW: Database + PgBouncer per cloud
│   ├── cloud-secrets/               # NEW: Secret store entry per cloud
│   ├── cloud-redis/                 # NEW: Redis per cloud
│   └── cloud-kafka/                 # NEW: Kafka/event streaming per cloud
└── teams/
    └── <team>/
        └── <service>/
            ├── main.tf              # Orchestrates all modules
            ├── variables.tf
            └── terraform.tfvars     # Cloud-specific config
```

### Per-service Terraform

```hcl
# terraform/teams/payments/payments-api/main.tf

locals {
  cloud = {
    provider = var.cloud_provider     # local | gcp | aws | azure
    region   = var.cloud_region
    project  = var.cloud_project      # GCP project ID (if gcp)
  }
}

# 1. IAM / Identity
module "iam" {
  source = "../../modules/cloud-iam"
  name   = "payments-api"
  cloud  = local.cloud
  k8s_service_accounts = [
    "payments-api-production/payments-api",
    "payments-api-production/payments-worker",
  ]
}

# 2. Secrets backend entry
module "secrets" {
  source = "../../modules/cloud-secrets"
  name   = "payments-api"
  cloud  = local.cloud
  accessors = [module.iam.service_account_email]  # cloud-specific
}

# 3. Database (if needed)
module "database" {
  source = "../../modules/cloud-database"
  name   = "payments-api"
  cloud  = local.cloud
  tier   = "standard"    # small | standard | large
  ha     = true
}

# 4. Redis (if needed)
module "redis" {
  source = "../../modules/cloud-redis"
  name   = "payments-api"
  cloud  = local.cloud
  size_gb = 4
}

# 5. Kafka / event streaming (if needed)
module "kafka" {
  source = "../../modules/cloud-kafka"
  name   = "payments-api"
  cloud  = local.cloud
  topics = ["payments-api.events", "payments-api.payments", "payments-api.transactions"]
  # CDC source (Debezium) — captures DB changes → Kafka topics
  cdc = {
    enabled    = true
    pg_host    = module.database.host
    pg_port    = 5432
    pg_database = "payments_api"
    tables     = ["payments", "transactions", "refunds"]
  }
}

# 6. Generate env YAML (existing module)
module "service_descriptors" {
  source = "../../modules/nqlabs-service"
  name   = "payments-api"
  apps_root = "../../../apps"
  environments = {
    staging = {
      image_repository = "ghcr.io/nicolasqueiroga/payments-api"
      image_tag        = "REPLACE_ON_FIRST_DEPLOY"
      ...
    }
    production = {
      image_repository = "ghcr.io/nicolasqueiroga/payments-api"
      image_tag        = "REPLACE_ON_FIRST_DEPLOY"
      ...
    }
  }
}
```

### Cloud-iam module (example)

```hcl
# terraform/modules/cloud-iam/main.tf

variable "name"     { type = string }
variable "cloud"    { type = object({ provider = string, region = string, project = string }) }
variable "k8s_service_accounts" { type = list(string) }

# GCP
resource "google_service_account" "service" {
  count      = var.cloud.provider == "gcp" ? 1 : 0
  account_id = var.name
  project    = var.cloud.project
}

resource "google_service_account_iam_binding" "wif" {
  count              = var.cloud.provider == "gcp" ? 1 : 0
  service_account_id = google_service_account.service[0].name
  role               = "roles/iam.workloadIdentityUser"
  members = [
    for sa in var.k8s_service_accounts :
    "serviceAccount:${var.cloud.project}.svc.id.goog[${sa}]"
  ]
}

# AWS
resource "aws_iam_role" "service" {
  count = var.cloud.provider == "aws" ? 1 : 0
  name  = var.name
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:sub" = "repo:NicolasQueiroga/${var.name}:ref:refs/heads/main"
        }
      }
    }]
  })
}

# Azure
resource "azurerm_user_assigned_identity" "service" {
  count               = var.cloud.provider == "azure" ? 1 : 0
  name                = var.name
  resource_group_name = var.cloud.resource_group
  location            = var.cloud.region
}

# Local: no-op (K8s SA handles identity)
```

---

## 9. Implementation Phases

### Phase 0: Team Creation

**Goal:** Introduce teams as a first-class concept — the prerequisite
organizational unit for service creation.

**Steps:**
1. Create `team-create.yaml` workflow (manual trigger with team name + leads)
2. Workflow creates:
   - Authentik group via blueprint
   - ArgoCD AppProjects: `<team>-staging`, `<team>-production`, `<team>-preview`
   - Infisical project scoped to team
   - ArgoCD RBAC: team group → manage apps in `<team>-*` projects
   - Infisical RBAC: team group → access team project
   - `terraform/teams/<team>/` directory
3. Update `app-create.yaml` to accept a `team` parameter
4. Update ApplicationSet to use team-scoped AppProjects

**Deliverables:**
- `team-create.yaml` workflow
- Team-scoped AppProjects and RBAC
- `app-create.yaml` accepts team parameter

**Estimated effort:** 1 session

### Phase 1: Secrets Provider Abstraction + Infisical Migration

**Goal:** Replace OpenBao with Infisical as the local secrets backend and make
the store name configurable per environment.

**Steps:**
1. Deploy Infisical via Helm (CloudNativePG backend, Authentik OIDC)
2. Configure Infisical OIDC with Authentik (web UI)
3. Create Machine Identity with Kubernetes Auth
4. Create `ClusterSecretStore` (`nqlabs-infisical`)
5. Migrate secrets from OpenBao KV to Infisical
6. Update environment YAMLs: `externalSecrets.store: nqlabs-infisical`
7. Verify all ExternalSecrets sync
8. Keep OpenBao PKI engine for cert-manager (no change)

**Deliverables:**
- Infisical running in management cluster
- OIDC SSO working with Authentik
- All secrets migrated to Infisical
- ESO ClusterSecretStore updated

**Estimated effort:** 1-2 sessions

### Phase 2: CI/CD Deploy Automation

**Goal:** Build the `github-builder` equivalent — automated deploy workflow
that updates GitOps state and triggers ArgoCD sync.

**Steps:**
1. Create `deploy-reusable.yaml` in platform repo
2. Create app repo workflow templates (build, deploy-staging, deploy-production)
3. Test end-to-end with the demo service
4. Document the app repo onboarding process

**Deliverables:**
- `deploy-reusable.yaml` workflow
- App repo workflow templates
- End-to-end test: merge to main → staging deploys automatically

**Estimated effort:** 1-2 sessions

### Phase 3: Identity Provider Abstraction

**Goal:** Make the service chart provider-aware for service account identity.

**Steps:**
1. Add `serviceAccount.identity` field to the chart values schema
2. Update `serviceaccount.yaml` template to render provider-specific annotations
3. Test with local (no-op) and verify existing services still work
4. Document the identity provider configuration

**Deliverables:**
- Chart supports `identity.provider: none | gcp-wif | aws-irsa | azure-mi`
- Existing services unaffected (default: `none`)

**Estimated effort:** 1 session

### Phase 3.5: Observability Automation

**Goal:** Make every new service automatically appear in uptime checks,
alerts, dashboards, and traces — with zero manual configuration.

**Steps:**
1. Add `gatus.yaml` template to the chart:
   - Generates a ConfigMap with a Gatus endpoint entry
   - A controller or kustomize component merges per-service ConfigMaps
     into the central Gatus config (or Gatus watches labeled ConfigMaps)
2. Add `prometheusrule.yaml` template to the chart:
   - Default alert rules: high 5xx rate, high latency (p99), pod restarts,
     OOMKilled, HPA maxed out
   - Parameterized by service name and severity
3. Add `grafanadashboard.yaml` template to the chart:
   - Generates a ConfigMap with `grafana_dashboard` label
   - Default dashboard: request rate, error rate, latency p50/p95/p99,
     pod CPU/memory, restart count
   - Grafana sidecar provisioner auto-imports ConfigMaps with this label
4. Add `otel.yaml` template to the chart:
   - Injects OTel environment variables into the pod spec
   - `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_SERVICE_NAME`
   - Services using OTel SDKs automatically send traces to OTel Collector → Tempo
5. Ensure data layer services (CNPG, Valkey, Redpanda) also get
   ServiceMonitors, PrometheusRules, and Gatus checks via their Terraform modules

**Deliverables:**
- Chart generates Gatus, PrometheusRule, Grafana dashboard, OTel templates
- New service appears in Gatus, Alertmanager, Grafana, and Tempo automatically
- Data layer services have their own observability resources

**Estimated effort:** 1-2 sessions

### Phase 4: Data Layer (Database + PgBouncer + Redis)

**Goal:** Automated per-service database, connection pooling, and Redis
provisioning. Needed when staging/production clusters run real services.

**Steps:**
1. Create `cloud-database` Terraform module:
   - Generates CloudNativePG `Cluster` + `Database` manifests
   - Generates CNPG `Pooler` manifest (PgBouncer, managed by CNPG)
   - Supports tiers: small (1 replica) / standard (HA, 1 primary + 1 replica) / large
2. Create `cloud-redis` Terraform module:
   - Generates Valkey StatefulSet with persistent storage
   - Supports single-node (staging) and HA (production) configs
3. Add database + Redis provisioning to the service creation flow
4. Test with a service that needs both

**Deliverables:**
- `terraform/modules/cloud-database/` module (CNPG Cluster + Pooler)
- `terraform/modules/cloud-redis/` module (Valkey StatefulSet)
- Per-service database + Redis provisioning via Terraform
- Documentation

**Estimated effort:** 2-3 sessions

### Phase 5: Event Streaming (Kafka / Redpanda)

**Goal:** Kafka-compatible event streaming infrastructure for async messaging
and CDC between services.

**Steps:**
1. Deploy Redpanda in K8s (Helm chart, no ZooKeeper)
2. Create `cloud-kafka` Terraform module:
   - Provisions Kafka topics for async messaging/queues
   - Optional Debezium CDC source (captures DB changes → topics)
   - Optional sink connectors (e.g., object storage for analytics)
3. Add Kafka topic provisioning to the service creation flow
4. Test with a service that needs event streaming

**Deliverables:**
- Redpanda running in staging/production clusters
- `terraform/modules/cloud-kafka/` module
- Per-service topic + CDC provisioning via Terraform
- Documentation

**Estimated effort:** 2-3 sessions

### Phase 6: Cloud IaC Modules

**Goal:** Terraform modules for GCP, AWS, Azure infrastructure. Only needed
when deploying to a cloud.

**Steps:**
1. Create `cloud-iam` module (GCP first, then AWS, then Azure)
2. Create `cloud-secrets` module (GCP SM, AWS SM, Azure KV)
3. Expand `cloud-database` module (CloudSQL, RDS, Azure DB + PgBouncer/RDS Proxy)
4. Expand `cloud-redis` module (Memorystore, ElastiCache, Azure Cache)
5. Expand `cloud-kafka` module (Confluent Cloud, MSK, Event Hubs)
6. Test with a cloud deployment (when ready)

**Deliverables:**
- Multi-cloud Terraform modules
- Service creation works on GCP/AWS/Azure with minimal changes

**Estimated effort:** 3-5 sessions (only needed when deploying to a cloud)

---

## 10. Key Decisions and Tradeoffs

### Decision 1: ESO as the secrets abstraction layer

**Choice:** Use ESO (already running) with swappable backends.
**Alternative:** Use Infisical's native Kubernetes Operator (tighter integration
but locks into Infisical).
**Rationale:** ESO supports all backends (Infisical, OpenBao, GCP SM, AWS SM,
Azure KV, 1Password). The service descriptor just changes the store name. This
is the lowest-friction path to cloud-agnosticism. The Infisical Operator is an
option for the future if we want tighter integration (auto-reload, push secrets).

### Decision 2: Infisical over OpenBao for local secrets

**Choice:** Switch from OpenBao to Infisical for the local secrets backend.
**Alternative:** Keep OpenBao (already working, but painful OIDC integration).
**Rationale:** Infisical has easier OIDC integration (web UI vs API calls),
simpler operational model (PostgreSQL vs Raft + unsealing), and uses CloudNativePG
which is already running. The state loss risk that occurred this session (OpenBao
cluster re-init wiped all KV data) is eliminated with a PostgreSQL backend.
**Tradeoff:** OpenBao's PKI engine is more mature; we keep it for cert-manager
signing but use Infisical for secret storage.

### Decision 3: Cloud-native secret managers for cloud deployments

**Choice:** Use GCP Secret Manager / AWS Secrets Manager / Azure Key Vault on
cloud (not Infisical or OpenBao).
**Alternative:** Run Infisical on cloud (self-hosted).
**Rationale:** Cloud-native secret managers are managed, cheaper, more reliable,
and require no ops. ESO supports all of them. The service descriptor just changes
the store name. Running Infisical on cloud would add operational burden for no
benefit.

### Decision 4: Single repo with clear directory structure

**Choice:** Keep everything in `nqlabs-platform` with clear directory separation.
**Alternative:** Split into multiple repos (like the enterprise: terraform,
terraform-data, monorepo-gitops, resources-provisioning).
**Rationale:** For a home lab / small team, a single repo is simpler to manage.
The directory structure already mirrors the multi-repo approach. If the platform
grows significantly, splitting into repos is straightforward (the directory
boundaries are already clear).

### Decision 5: Terraform with provider switch for cloud IaC

**Choice:** One Terraform module per concern (IAM, database, secrets, redis)
with a `cloud.provider` variable that switches between implementations.
**Alternative:** Separate Terraform modules per cloud (e.g., `gcp-iam`, `aws-iam`).
**Rationale:** The provider switch keeps the service-level Terraform
(`terraform/services/<service>/main.tf`) the same regardless of cloud. Only the
module internals change. This is the same pattern as the `provider` block in
the environment YAML.

### Decision 6: GHCR for local, cloud-native registries for cloud

**Choice:** Use GHCR (GitHub Container Registry) for local deployments,
cloud-native registries (GCR, ECR, ACR) for cloud deployments.
**Alternative:** Run a self-hosted registry (Harbor) locally.
**Rationale:** GHCR is free, works everywhere, and integrates with GitHub Actions
(seamless auth via GITHUB_TOKEN). A self-hosted registry adds operational burden
(storage, backup, replication) for no benefit in a home lab. If supply chain
requirements change (e.g., air-gapped deployment), Harbor can be added later.

### Decision 7: Keep OpenBao PKI for cert-manager

**Choice:** Keep the OpenBao PKI engine for cert-manager certificate signing,
even after switching to Infisical for secret storage.
**Alternative:** Migrate PKI to Infisical's Machine Identity or cert-manager's
built-in CA.
**Rationale:** The PKI engine is already bootstrapped and working. The
ClusterIssuer (`nqlabs-openbao-pki`) is configured and signing certificates.
Migrating it would add risk for no benefit. OpenBao can run in a minimal
configuration (PKI engine only, no KV, no auth methods) just for cert signing.

---

## 11. Platform Integration Requirements

Every new piece of infrastructure and every new service must be a first-class
citizen of the existing platform stack. "Runs in Kubernetes" is not enough.

### Existing platform services

| Platform service | What it provides | How new infra/services integrate |
|---|---|---|
| **Authentik** | OIDC/SAML SSO, forward-auth proxy, group RBAC | Infisical: OIDC SSO (native). Redpanda admin UI: Authentik proxy outpost. Any web-accessible service: OIDC or proxy. Team groups control access. |
| **Rook/Ceph** | Block (RBD), Object (RGW/S3), Filesystem (CephFS) | All persistent data services use Ceph RBD StorageClass for PVCs: CloudNativePG (WAL + data), Valkey (persistence), Redpanda (data). Backups target Ceph RGW (S3) or Cloudflare R2. |
| **cert-manager** | TLS certificates (OpenBao PKI + Let's Encrypt) | Every HTTPS endpoint gets a cert-manager certificate via the existing ClusterIssuer. Infisical, Redpanda admin UI, per-service HTTPRoutes. |
| **Cilium** | CNI, network policies, Gateway API, Hubble | Every service gets a CiliumNetworkPolicy (default-deny ingress, allow owning service). Data services (CNPG, Valkey, Redpanda) are isolated — only the owning service namespace can reach them. HTTPRoutes via the platform Gateway. |
| **External Secrets Operator** | Secret sync from backend → K8s Secret | Infisical becomes an ESO backend (ClusterSecretStore `nqlabs-infisical`). Per-service ExternalSecrets reference the store. |
| **Kyverno** | Policy enforcement (image allowlist, pod security) | All new images must be in the Kyverno image allowlist (or namespace excluded with justification). Pod security policies (non-root, read-only fs, seccomp) enforced. |
| **Falco** | Runtime security | Applies to all pods automatically. Alert rules for suspicious activity in data services (e.g., unexpected file access in CNPG pods). |
| **Velero** | Backup/restore | Data services backed up via Velero with appropriate schedules. CNPG: Velero + CNPG barman backups. Valkey: Velero snapshot of PVC. Redpanda: Velero snapshot of PVC. Backups target Ceph RGW + Cloudflare R2. |
| **ArgoCD** | GitOps deployment | All new infrastructure deployed and managed via ArgoCD. No manual kubectl. Manifests in `infrastructure/` directory. |
| **OpenBao PKI** | Certificate signing for cert-manager | Unchanged. cert-manager ClusterIssuer `nqlabs-openbao-pki` continues signing all internal TLS certs. |

### Observability stack — automatic integration

This is the critical requirement: **when a service is created, it must
automatically appear in logs, metrics, traces, uptime, alerts, and
dashboards — with zero manual configuration.**

#### What the chart already generates (✅)

| Capability | How | Template |
|---|---|---|
| **Metrics** | ServiceMonitor → Prometheus scrapes `/metrics` | `servicemonitor.yaml` |
| **Logs** | Promtail collects all pod logs by default → Loki | (no template needed — Promtail is cluster-wide) |
| **Network isolation** | CiliumNetworkPolicy (default-deny ingress) | `ciliumnetworkpolicy.yaml` |
| **Canary analysis** | AnalysisTemplate (HTTP 2xx rate during rollout) | `analysistemplate.yaml` |

#### What's missing — needs to be added to the chart (❌)

| Capability | How | What needs to be built |
|---|---|---|
| **Uptime** | Gatus endpoint check | New template `gatus.yaml` — generates a ConfigMap with a Gatus endpoint entry. A controller or kustomize component merges per-service ConfigMaps into the central Gatus config. Alternatively, Gatus watches a ConfigMap with a specific label and auto-discovers endpoints. |
| **Alerts** | PrometheusRule per service | New template `prometheusrule.yaml` — generates default alert rules: high 5xx rate, high latency (p99 > threshold), pod restarts, OOMKilled, HPA maxed out. Rules are parameterized by service name and severity. |
| **Dashboards** | Grafana dashboard ConfigMap | New template `grafanadashboard.yaml` — generates a ConfigMap with `grafana_dashboard` label containing a default dashboard (request rate, error rate, latency p50/p95/p99, pod CPU/memory, restart count). Grafana sidecar provisioner auto-imports ConfigMaps with this label. |
| **Traces** | OTel instrumentation | New template `otel.yaml` — optionally injects OTel environment variables (`OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_SERVICE_NAME`) into the pod spec. Services using OTel SDKs automatically send traces to the OTel Collector → Tempo. No sidecar needed for SDK-based instrumentation. |

#### Observability integration design

```
Service created via app-create.yaml
  │
  ├── Chart renders (existing):
  │   ├── ServiceMonitor          → Prometheus scrapes metrics
  │   ├── CiliumNetworkPolicy     → network isolation
  │   ├── AnalysisTemplate        → canary analysis during rollout
  │   └── HTTPRoute               → Gateway API routing
  │
  ├── Chart renders (NEW — to be added):
  │   ├── Gatus endpoint ConfigMap → Gatus starts uptime checking
  │   ├── PrometheusRule          → Alertmanager gets default alert rules
  │   ├── GrafanaDashboard CM     → Grafana auto-imports default dashboard
  │   └── OTel env vars           → traces flow to OTel Collector → Tempo
  │
  └── Automatic (no template needed):
      ├── Promtail → Loki         → logs collected cluster-wide
      └── Falco                   → runtime security monitored cluster-wide
```

#### Data layer observability

When the Terraform modules provision data services, they must also generate
the observability resources:

| Data service | Metrics | Logs | Uptime | Alerts |
|---|---|---|---|---|
| **CloudNativePG** | CNPG Prometheus exporter → ServiceMonitor | Promtail (automatic) | Gatus: `pg_isready` check | PrometheusRule: replication lag, connection pool saturation, WAL backlog, disk usage |
| **PgBouncer (CNPG Pooler)** | PgBouncer Prometheus exporter → ServiceMonitor | Promtail (automatic) | Gatus: pooler health endpoint | PrometheusRule: pool exhaustion, max client connections |
| **Valkey** | Valkey exporter → ServiceMonitor | Promtail (automatic) | Gatus: `PING` check | PrometheusRule: memory usage > 90%, evicted keys, connected clients |
| **Redpanda** | Redpanda Prometheus metrics → ServiceMonitor | Promtail (automatic) | Gatus: Kafka API health endpoint | PrometheusRule: consumer lag, partition under-replicated, disk usage |
| **Infisical** | Infisical metrics → ServiceMonitor | Promtail (automatic) | Gatus: Infisical health endpoint | PrometheusRule: secret sync failures, API errors |

### Per-service integration checklist

When a new service is created via `app-create.yaml`, the chart generates:

**Already implemented (✅):**
- ✅ HTTPRoute (Gateway API) — internal route, optional public route
- ✅ ExternalSecret — references the configured ClusterSecretStore
- ✅ ServiceMonitor — Prometheus scraping
- ✅ CiliumNetworkPolicy — default-deny ingress, allow cluster entities
- ✅ ServiceAccount — with optional cloud identity annotations
- ✅ PDB + HPA — availability and scaling
- ✅ Resource requests/limits — per environment
- ✅ Pod security — seccomp, non-root, read-only fs, drop ALL caps
- ✅ AnalysisTemplate — canary analysis during rollout

**To be added (❌):**
- ❌ Gatus uptime check — auto-register service endpoint
- ❌ PrometheusRule — default alert rules (5xx, latency, restarts, OOM)
- ❌ Grafana dashboard — default dashboard ConfigMap (request rate, error rate, latency, resources)
- ❌ OTel env vars — trace export config for SDK-based instrumentation

**For services that need data layer (Terraform modules generate):**
- ❌ CNPG Cluster + Pooler — Ceph RBD StorageClass, CiliumNetworkPolicy, ServiceMonitor, PrometheusRule, Velero backup
- ❌ Valkey StatefulSet — Ceph RBD StorageClass, CiliumNetworkPolicy, ServiceMonitor, PrometheusRule
- ❌ Redpanda topics — CiliumNetworkPolicy, ServiceMonitor, PrometheusRule

### Resource planning

Running the full data layer stack on the management cluster is **not
recommended** — these are workload services that belong on staging/production
clusters:

| Component | Where it runs | Est. resources (small) |
|---|---|---|
| Infisical | Management cluster (platform service) | 1-2 GB RAM, 5-10 GB storage (CNPG) |
| Per-service CNPG | Staging/production clusters | 1-2 GB RAM per cluster, 10-50 GB storage |
| Per-service Valkey | Staging/production clusters | 256-512 MB RAM, 1-5 GB storage |
| Redpanda | Staging/production clusters | 2-4 GB RAM, 20-50 GB storage per broker |

The management cluster runs platform services (Authentik, ArgoCD, monitoring,
Infisical, ESO, cert-manager). Staging/production clusters run application
workloads + their data layer (CNPG, Valkey, Redpanda).

---

## 12. Summary

```
                    CLOUD-AGNOSTIC SERVICE FACTORY

  Service descriptor (app.yaml + environments/*.yaml)
    │
    ├── provider.cloud: local | gcp | aws | azure
    ├── provider.secrets.store: nqlabs-infisical | gcp-sm | aws-sm | azure-kv
    ├── provider.identity: none | gcp-wif | aws-irsa | azure-mi
    └── provider.registry: ghcr.io | gcr.io | ecr | acr
    │
    ▼
  charts/nqlabs-service (renders K8s manifests)
    │
    ├── Deployment/Rollout + HPA + PDB + Service
    ├── HTTPRoute (Gateway API: internal, public, preview)
    ├── ExternalSecret (references ClusterSecretStore by name)
    ├── ServiceAccount (with cloud identity annotations)
    ├── ServiceMonitor + CiliumNetworkPolicy + RBAC
    ├── ConfigMap + ResourceQuota + LimitRange
    ├── [NEW] Gatus uptime check (auto-register endpoint)
    ├── [NEW] PrometheusRule (default alert rules per service)
    ├── [NEW] Grafana dashboard ConfigMap (auto-provisioned dashboard)
    └── [NEW] OTel env vars (trace export to OTel Collector → Tempo)
    │
    ▼
  ArgoCD ApplicationSet (deploys by cluster name)
    │
    ├── nqlabs-staging    → staging cluster
    └── nqlabs-production → production cluster

  SECRETS BACKEND (per cluster, via ESO):
    Local  → Infisical (self-hosted, PostgreSQL, Authentik OIDC)
    GCP    → GCP Secret Manager (managed)
    AWS    → AWS Secrets Manager (managed)
    Azure  → Azure Key Vault (managed)

  CLOUD IaC (Terraform, per team/service):
    Local  → CNPG + PgBouncer + Valkey + Redpanda (all in K8s)
    GCP    → GKE + CloudSQL + Memorystore + Confluent + WIF + Secret Manager
    AWS    → EKS + RDS + ElastiCache + MSK + IRSA + Secrets Manager
    Azure  → AKS + Azure DB + Azure Cache + Event Hubs + MI + Key Vault

  CI/CD:
    App repo → build → push to registry → call deploy-reusable
    Platform → deploy-reusable updates GitOps → ArgoCD syncs
```

The platform is ~80% built. The remaining work is:
1. **Phase 0:** Team creation workflow (1 session)
2. **Phase 1:** Switch to Infisical (1-2 sessions)
3. **Phase 2:** CI/CD deploy automation (1-2 sessions)
4. **Phase 3:** Identity provider abstraction (1 session)
5. **Phase 3.5:** Observability automation — add Gatus, PrometheusRule, Grafana dashboard, OTel templates to the chart (1-2 sessions)
6. **Phase 4:** Data layer — Database + PgBouncer + Redis (2-3 sessions)
7. **Phase 5:** Event streaming — Kafka/Redpanda (2-3 sessions)
8. **Phase 6:** Cloud IaC modules (3-5 sessions, only when deploying to cloud)
