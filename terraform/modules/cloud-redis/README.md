# cloud-redis

Managed Redis provisioning across GCP (Memorystore), AWS (ElastiCache), and Azure (Cache for Redis). Pairs with the `cloud-iam` and `cloud-secrets` modules for identity and secret access.

For in-cluster deployments, use the `redis.enabled = true` values in `charts/nqlabs-service` instead — this module is for cloud-hosted Redis only.

## Tier table

| Tier     | GCP                  | AWS                       | Azure          |
|----------|----------------------|---------------------------|----------------|
| small    | BASIC, 1 GB          | cache.t4g.micro, 1 node   | Basic C0       |
| standard | STANDARD_HA, 2 GB    | cache.t4g.micro, 2 nodes  | Standard C1    |
| large    | STANDARD_HA, 4 GB    | cache.t4g.medium, 2 nodes | Premium P1     |

## GCP (Memorystore)

```hcl
module "redis" {
  source = "../../modules/cloud-redis/gcp"

  project               = "my-project"
  region                = "us-central1"
  service_name          = "payments"
  environment           = "production"
  tier                  = "standard"
  service_account_email = module.iam.service_account_email
  authorized_network    = "projects/my-project/global/networks/default"
}
```

The Redis connection info is stored in Secret Manager at `payments/production/redis` (with properties `host`, `port`, `auth_string`, `redis_url`). The service account is granted `secretAccessor`.

## AWS (ElastiCache)

```hcl
module "redis" {
  source = "../../modules/cloud-redis/aws"

  service_name        = "payments"
  environment         = "production"
  region              = "us-east-1"
  tier                = "standard"
  vpc_id              = "vpc-xxxxxxxx"
  subnet_ids          = ["subnet-aaa", "subnet-bbb"]
  allowed_cidr_blocks = ["10.0.0.0/16"]
  role_name           = module.iam.role_name
}
```

Connection info is stored in Secrets Manager at `payments/production/redis`. The IAM role receives a policy to read the secret.

## Azure (Cache for Redis)

```hcl
module "redis" {
  source = "../../modules/cloud-redis/azure"

  service_name        = "payments"
  environment         = "production"
  resource_group_name = "payments-rg"
  location            = "eastus"
  tier                = "standard"
  key_vault_id        = module.secrets.key_vault_id
}
```

Connection info is stored in Key Vault as `payments-production-redis`. Use `azurerm_key_vault_access_policy` (from `cloud-secrets/azure`) to grant the managed identity read access.
