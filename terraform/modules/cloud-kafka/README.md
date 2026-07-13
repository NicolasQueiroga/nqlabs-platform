# cloud-kafka

Managed Kafka for cloud deployments. Three sub-modules, one per provider.

For the in-cluster (home-lab) path, use the `nqlabs-service` chart with
`kafka.enabled=true` — that provisions Strimzi/Kafka topics via a PostSync Job.
These modules are the cloud equivalent.

---

## Sub-modules

| Sub-module | Provider | What it creates |
|---|---|---|
| `confluent/` | Confluent Cloud (multi-cloud: GCP/AWS/Azure) | Environment, Kafka cluster (Basic or Dedicated), service account, topics, PRODUCER+CONSUMER ACLs, API key |
| `msk/` | AWS | MSK Kafka 3.x cluster, SASL/SCRAM secrets in Secrets Manager, security group |
| `event-hubs/` | Azure | Event Hubs namespace (Premium, Kafka-compatible), Event Hubs (topics), authorization rule |

---

## confluent/

Confluent Cloud is provider-agnostic — the same module works whether your
cluster runs on GCP, AWS, or Azure. Recommended for multi-cloud setups or
when you want a fully-managed Kafka with a single operational model.

```hcl
module "kafka" {
  source = "../../modules/cloud-kafka/confluent"

  service_name     = "payments"
  environment      = "production"
  cloud_provider   = "GCP"
  region           = "us-central1"
  tier             = "dedicated"   # basic | dedicated
  confluent_environment_id = var.confluent_env_id  # empty = create one

  topics = [
    { name = "payments.payment-initiated", partitions = 6 },
    { name = "payments.payment-completed", partitions = 6 },
    { name = "payments.payment-failed",    partitions = 3,
      config = { "retention.ms" = "604800000" } },
  ]
}

output "bootstrap" { value = module.kafka.bootstrap_endpoint }
# Use module.kafka.api_key + module.kafka.api_secret for SASL_SSL auth.
```

Required provider configuration:
```hcl
provider "confluent" {
  cloud_api_key    = var.confluent_cloud_api_key
  cloud_api_secret = var.confluent_cloud_api_secret
}
```

---

## msk/

AWS-native. Uses SASL/SCRAM with credentials stored in Secrets Manager
(prefixed `AmazonMSK_` as required). TLS-only transport.

```hcl
module "kafka" {
  source = "../../modules/cloud-kafka/msk"

  service_name = "payments"
  environment  = "production"
  region       = "us-east-1"
  vpc_id       = var.vpc_id
  subnet_ids   = var.private_subnet_ids
  tier         = "standard"   # small (1 broker) | standard (3 brokers)
  sasl_users   = ["payments-producer", "payments-consumer"]
}

output "brokers" { value = module.kafka.bootstrap_brokers_sasl_scram }
# Credentials in module.kafka.sasl_secret_arns
```

---

## event-hubs/

Azure Event Hubs Premium exposes a Kafka-compatible endpoint on port 9093
using SASL/PLAIN over TLS. The connection string from the authorization rule
is used as the Kafka password.

```hcl
module "kafka" {
  source = "../../modules/cloud-kafka/event-hubs"

  service_name        = "payments"
  environment         = "production"
  resource_group_name = var.rg_name
  location            = "eastus"
  retention_days      = 7

  topics = [
    { name = "payments-payment-initiated", partitions = 4 },
    { name = "payments-payment-completed", partitions = 4 },
    { name = "payments-payment-failed",    partitions = 2 },
  ]
}

# Kafka config:
#   bootstrap.servers = module.kafka.kafka_endpoint
#   security.protocol = SASL_SSL
#   sasl.mechanism    = PLAIN
#   sasl.username     = "$ConnectionString"
#   sasl.password     = module.kafka.connection_string  (sensitive)
```

---

## Choosing a sub-module

| Factor | Confluent | MSK | Event Hubs |
|---|---|---|---|
| Cloud-agnostic | Yes | AWS only | Azure only |
| Fully managed | Yes | Yes | Yes |
| Kafka compatibility | Full | Full | Partial (no compacted topics) |
| Auth | API Key (SASL_SSL) | SASL/SCRAM | SASL/PLAIN |
| In-cluster alternative | `kafka.enabled=true` in chart (Strimzi/Kafka) | same | same |
