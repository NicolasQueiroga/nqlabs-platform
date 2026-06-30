# cloud-iam

Terraform sub-modules that provision the cloud-side identity resources pairing
with the `serviceAccount.identity` value in `charts/nqlabs-service`.

Each sub-module lives under its provider directory: `gcp/`, `aws/`, `azure/`.
Use only the provider that matches the target cluster.

## How it pairs with the chart

The `nqlabs-service` chart renders cloud-specific annotations on the Kubernetes
ServiceAccount based on `serviceAccount.identity.provider`:

| provider   | chart annotation                                          | module output to use           |
|------------|-----------------------------------------------------------|--------------------------------|
| `gcp-wif`  | `iam.gke.io/gcp-service-account: <email>`                 | `gcp.service_account_email`    |
| `aws-irsa` | `eks.amazonaws.com/role-arn: <arn>`                       | `aws.role_arn`                 |
| `azure-mi` | `azure.workload.identity/client-id: <client_id>`          | `azure.client_id`              |
| `none`     | (no annotation — local cluster, no cloud identity needed) | —                              |

The cloud module creates the identity resource and binds it to the Kubernetes
ServiceAccount's token so cloud APIs accept the pod's OIDC credential.

---

## GCP — Workload Identity Federation

Creates a GCP Service Account, optional Workload Identity pool/provider (once
per cluster), and the `workloadIdentityUser` binding.

```hcl
module "payments_gcp_iam" {
  source = "../../modules/cloud-iam/gcp"

  project          = "my-gcp-project"
  service_name     = "payments"
  environment      = "production"
  namespace        = "payments-production"
  cluster_name     = "nqlabs-production"
  cluster_location = "us-central1"

  # Create the pool once for the cluster; all other services set this to false
  # and pass the pool ID produced by the first service.
  create_pool               = true
  workload_identity_pool_id = ""

  roles = [
    "roles/cloudtasks.enqueuer",
    "roles/secretmanager.secretAccessor",
  ]
}

# In the service's environment YAML:
# serviceAccount:
#   identity:
#     provider: gcp-wif
#     gcpServiceAccount: <module.payments_gcp_iam.service_account_email>
```

### Sharing the pool across services

The Workload Identity pool is a cluster-level resource. Create it with the
first service (`create_pool = true`), then pass its ID to all others:

```hcl
module "orders_gcp_iam" {
  source = "../../modules/cloud-iam/gcp"
  # ...
  create_pool               = false
  workload_identity_pool_id = module.payments_gcp_iam.workload_identity_pool_id
}
```

---

## AWS — IAM Roles for Service Accounts (IRSA)

Creates an IAM role with a trust policy scoped to the EKS OIDC provider and
the specific Kubernetes ServiceAccount. Attaches the caller-supplied managed
policy ARNs.

```hcl
module "payments_aws_iam" {
  source = "../../modules/cloud-iam/aws"

  service_name          = "payments"
  environment           = "production"
  namespace             = "payments-production"
  eks_oidc_provider_url = "oidc.eks.us-east-1.amazonaws.com/id/EXAMPL3ABCDEF"

  policy_arns = [
    "arn:aws:iam::123456789012:policy/PaymentsS3ReadPolicy",
    "arn:aws:iam::aws:policy/AmazonSQSFullAccess",
  ]
}

# In the service's environment YAML:
# serviceAccount:
#   identity:
#     provider: aws-irsa
#     awsRoleARN: <module.payments_aws_iam.role_arn>
```

---

## Azure — Workload Identity (User-Assigned Managed Identity)

Creates a user-assigned managed identity, a federated credential binding the
AKS OIDC token to the identity, and optional Azure role assignments.

```hcl
module "payments_azure_iam" {
  source = "../../modules/cloud-iam/azure"

  service_name        = "payments"
  environment         = "production"
  namespace           = "payments-production"
  resource_group_name = "nqlabs-rg"
  location            = "eastus"
  aks_oidc_issuer_url = "https://eastus.oic.prod-aks.azure.com/tenant-id/cluster-id/"

  role_assignments = [
    {
      scope                = "/subscriptions/xxx/resourceGroups/nqlabs-rg/providers/Microsoft.Storage/storageAccounts/nqlabsstorage"
      role_definition_name = "Storage Blob Data Reader"
    },
  ]
}

# In the service's environment YAML:
# serviceAccount:
#   identity:
#     provider: azure-mi
#     azureClientID: <module.payments_azure_iam.client_id>
#     azureTenantID: <module.payments_azure_iam.tenant_id>
```

---

## Notes

- All three modules are opt-in and independent. Use only the provider for the
  target cluster.
- `environment` is validated to `staging` or `production`. The same module is
  called once per environment — use separate Terraform workspaces or state files
  to avoid cross-environment drift.
- None of these modules write Kubernetes manifests directly. They produce output
  values (email, ARN, client ID) that are pasted into the service's environment
  YAML under `serviceAccount.identity`. The chart renders the annotation; the
  cloud runtime validates the token.
