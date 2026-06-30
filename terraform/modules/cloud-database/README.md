# cloud-database

Managed PostgreSQL for NQLabs services on GCP, AWS, and Azure.

This is the cloud equivalent of the in-cluster CloudNativePG path (enabled by
`database.enabled = true` in the `nqlabs-service` Helm chart). Use one or the other
per environment — not both.

## Tier reference

| Tier     | GCP                   | AWS              | Azure                  | HA       |
|----------|-----------------------|------------------|------------------------|----------|
| small    | db-f1-micro (zonal)   | db.t4g.micro     | B_Standard_B1ms        | No       |
| standard | db-n1-standard-2 (HA) | db.t4g.medium    | GP_Standard_D2s_v3     | Yes      |
| large    | db-n1-standard-4 (HA) | db.t4g.large     | GP_Standard_D4s_v3     | Yes      |

Recommendation: use `small` for staging, `standard` for production.

## How it fits together

```
cloud-iam/<provider>    →  cloud-database/<provider>  →  cloud-secrets/<provider>
  service_account_email       grants secretAccessor         (or Key Vault policy)
  role_name                   reads secret at deploy
  identity_object_id
```

The module stores connection details (username, password, host, database,
connection_url) in the cloud secret store so the platform ESO `ClusterSecretStore`
(or application pods via SDK) can retrieve `DATABASE_URL` at runtime.

Secret path convention:

| Provider | Path / Name                          |
|----------|--------------------------------------|
| GCP      | `<service>/<environment>/database`   |
| AWS      | `<service>/<environment>/database`   |
| Azure    | `<service>-<environment>-db`         |

## Usage — GCP

```hcl
module "iam" {
  source                = "../../modules/cloud-iam/gcp"
  project               = var.project
  region                = var.region
  service_name          = "payments"
  environment           = "production"
  cluster_name          = var.cluster_name
  cluster_location      = var.region
  roles                 = []
}

module "db" {
  source                = "../../modules/cloud-database/gcp"
  project               = var.project
  region                = var.region
  service_name          = "payments"
  environment           = "production"
  tier                  = "standard"
  deletion_protection   = true
  service_account_email = module.iam.service_account_email
}
```

## Usage — AWS

```hcl
module "iam" {
  source               = "../../modules/cloud-iam/aws"
  service_name         = "payments"
  environment          = "production"
  eks_oidc_provider_url = var.eks_oidc_provider_url
  policy_arns          = []
}

module "db" {
  source              = "../../modules/cloud-database/aws"
  service_name        = "payments"
  environment         = "production"
  region              = var.region
  tier                = "standard"
  vpc_id              = var.vpc_id
  subnet_ids          = var.private_subnet_ids
  allowed_cidr_blocks = [var.pod_cidr]
  role_name           = module.iam.role_name
  deletion_protection = true
}
```

## Usage — Azure

```hcl
module "iam" {
  source              = "../../modules/cloud-iam/azure"
  service_name        = "payments"
  environment         = "production"
  resource_group_name = var.resource_group_name
  location            = var.location
  aks_oidc_issuer_url = var.aks_oidc_issuer_url
}

module "secrets" {
  source              = "../../modules/cloud-secrets/azure"
  service_name        = "payments"
  environment         = "production"
  resource_group_name = var.resource_group_name
  location            = var.location
  identity_client_id  = module.iam.client_id
  tenant_id           = module.iam.tenant_id
}

module "db" {
  source              = "../../modules/cloud-database/azure"
  service_name        = "payments"
  environment         = "production"
  resource_group_name = var.resource_group_name
  location            = var.location
  tier                = "standard"
  key_vault_id        = module.secrets.key_vault_id
  identity_object_id  = module.iam.client_id
}
```
