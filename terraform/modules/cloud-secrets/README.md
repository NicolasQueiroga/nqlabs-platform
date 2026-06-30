# cloud-secrets

Provisions the cloud-side secret store resource for a service and grants read access
to the workload identity created by the `cloud-iam` module. Secret *values* are not
set here — only the resource shell and IAM binding.

Three provider sub-modules mirror the three providers in `cloud-iam`:

| Sub-module | Creates | IAM grant |
|---|---|---|
| `gcp/` | GCP Secret Manager secrets | `roles/secretmanager.secretAccessor` to WIF SA |
| `aws/` | AWS Secrets Manager secrets | Inline policy on IRSA role |
| `azure/` | Azure Key Vault (one per service/env) | `Get`+`List` access policy to MI |

---

## GCP

```hcl
module "iam" {
  source      = "../../modules/cloud-iam/gcp"
  project     = "my-project"
  service_name = "payments"
  namespace   = "payments-staging"
  environment = "staging"
  cluster_name     = "nqlabs-staging"
  cluster_location = "us-central1"
  roles = ["roles/cloudsql.client"]
}

module "secrets" {
  source                = "../../modules/cloud-secrets/gcp"
  project               = "my-project"
  service_name          = "payments"
  environment           = "staging"
  service_account_email = module.iam.service_account_email

  secrets = [
    { name = "database-url" },
    { name = "stripe-api-key", description = "Stripe secret key" },
  ]
}
```

Secret IDs created: `payments__staging__database-url`, `payments__staging__stripe-api-key`.
The running pod can fetch values via the GCP Secret Manager API using its WIF-bound SA.

---

## AWS

```hcl
module "iam" {
  source               = "../../modules/cloud-iam/aws"
  service_name         = "payments"
  namespace            = "payments-staging"
  environment          = "staging"
  eks_oidc_provider_url = "oidc.eks.us-east-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B716D3041E"
  policy_arns          = ["arn:aws:iam::aws:policy/AmazonRDSReadOnlyAccess"]
}

module "secrets" {
  source       = "../../modules/cloud-secrets/aws"
  service_name = "payments"
  environment  = "staging"
  region       = "us-east-1"
  role_name    = module.iam.role_name

  secrets = [
    { name = "database-url" },
    { name = "stripe-api-key" },
  ]
}
```

Secret paths created: `payments/staging/database-url`, `payments/staging/stripe-api-key`.
An inline IAM policy is attached to the IRSA role allowing `GetSecretValue` + `DescribeSecret`.

---

## Azure

```hcl
module "iam" {
  source              = "../../modules/cloud-iam/azure"
  service_name        = "payments"
  namespace           = "payments-staging"
  environment         = "staging"
  resource_group_name = "nqlabs-staging-rg"
  location            = "eastus"
  aks_oidc_issuer_url = "https://eastus.oic.prod-aks.azure.com/TENANT/CLUSTER/"
}

module "secrets" {
  source              = "../../modules/cloud-secrets/azure"
  service_name        = "payments"
  environment         = "staging"
  resource_group_name = "nqlabs-staging-rg"
  location            = "eastus"
  identity_client_id  = module.iam.client_id
  tenant_id           = module.iam.tenant_id
}
```

Creates Key Vault `kv-payments-staging`. The managed identity gets `Get`+`List` on secrets.
Secret values are added manually or via a CI pipeline (not by this module).

---

## Operating model

These modules follow the same scaffolding-only pattern as the rest of the platform's
Terraform: they write infrastructure resources, never secret values. Secret values
are loaded into the cloud store separately (by the service team or a sealed CI step)
and consumed by the workload at runtime via the cloud SDK or External Secrets Operator.
