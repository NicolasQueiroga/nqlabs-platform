locals {
  create_environment = var.confluent_environment_id == ""
  environment_id     = local.create_environment ? confluent_environment.this[0].id : var.confluent_environment_id
}

resource "confluent_environment" "this" {
  count        = local.create_environment ? 1 : 0
  display_name = "nqlabs-${var.environment}"
}

resource "confluent_kafka_cluster" "this" {
  display_name = "${var.service_name}-${var.environment}"
  availability = var.tier == "dedicated" ? "MULTI_ZONE" : "SINGLE_ZONE"
  cloud        = var.cloud_provider
  region       = var.region

  environment {
    id = local.environment_id
  }

  dynamic "basic" {
    for_each = var.tier == "basic" ? [1] : []
    content {}
  }

  dynamic "dedicated" {
    for_each = var.tier == "dedicated" ? [1] : []
    content {
      cku = 1
    }
  }
}

resource "confluent_service_account" "this" {
  display_name = "${var.service_name}-${var.environment}"
  description  = "Service account for ${var.service_name} in ${var.environment}"
}

resource "confluent_kafka_topic" "this" {
  for_each = { for t in var.topics : t.name => t }

  topic_name       = each.value.name
  partitions_count = each.value.partitions
  config           = each.value.config

  kafka_cluster {
    id = confluent_kafka_cluster.this.id
  }

  rest_endpoint = confluent_kafka_cluster.this.rest_endpoint

  credentials {
    key    = confluent_api_key.cluster_admin.id
    secret = confluent_api_key.cluster_admin.secret
  }
}

# Cluster-scoped admin key used only to provision topics. Not given to the service.
resource "confluent_service_account" "cluster_admin" {
  display_name = "${var.service_name}-${var.environment}-tf-admin"
  description  = "Terraform admin account for topic provisioning — not used by the service"
}

resource "confluent_role_binding" "cluster_admin" {
  principal   = "User:${confluent_service_account.cluster_admin.id}"
  role_name   = "CloudClusterAdmin"
  crn_pattern = confluent_kafka_cluster.this.rbac_crn
}

resource "confluent_api_key" "cluster_admin" {
  display_name = "${var.service_name}-${var.environment}-tf-admin"
  description  = "Terraform admin API key for topic provisioning"

  owner {
    id          = confluent_service_account.cluster_admin.id
    api_version = confluent_service_account.cluster_admin.api_version
    kind        = confluent_service_account.cluster_admin.kind
  }

  managed_resource {
    id          = confluent_kafka_cluster.this.id
    api_version = confluent_kafka_cluster.this.api_version
    kind        = confluent_kafka_cluster.this.kind

    environment {
      id = local.environment_id
    }
  }

  depends_on = [confluent_role_binding.cluster_admin]
}

# Service account API key — given to the service for produce/consume.
resource "confluent_api_key" "service" {
  display_name = "${var.service_name}-${var.environment}"
  description  = "Kafka API key for ${var.service_name} ${var.environment}"

  owner {
    id          = confluent_service_account.this.id
    api_version = confluent_service_account.this.api_version
    kind        = confluent_service_account.this.kind
  }

  managed_resource {
    id          = confluent_kafka_cluster.this.id
    api_version = confluent_kafka_cluster.this.api_version
    kind        = confluent_kafka_cluster.this.kind

    environment {
      id = local.environment_id
    }
  }
}

# Grant PRODUCER and CONSUMER ACLs on each topic to the service account.
resource "confluent_kafka_acl" "producer" {
  for_each = { for t in var.topics : t.name => t }

  kafka_cluster {
    id = confluent_kafka_cluster.this.id
  }

  resource_type = "TOPIC"
  resource_name = each.value.name
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.this.id}"
  host          = "*"
  operation     = "WRITE"
  permission    = "ALLOW"

  rest_endpoint = confluent_kafka_cluster.this.rest_endpoint
  credentials {
    key    = confluent_api_key.cluster_admin.id
    secret = confluent_api_key.cluster_admin.secret
  }
}

resource "confluent_kafka_acl" "consumer" {
  for_each = { for t in var.topics : t.name => t }

  kafka_cluster {
    id = confluent_kafka_cluster.this.id
  }

  resource_type = "TOPIC"
  resource_name = each.value.name
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.this.id}"
  host          = "*"
  operation     = "READ"
  permission    = "ALLOW"

  rest_endpoint = confluent_kafka_cluster.this.rest_endpoint
  credentials {
    key    = confluent_api_key.cluster_admin.id
    secret = confluent_api_key.cluster_admin.secret
  }
}

resource "confluent_kafka_acl" "consumer_group" {
  for_each = { for t in var.topics : t.name => t }

  kafka_cluster {
    id = confluent_kafka_cluster.this.id
  }

  resource_type = "GROUP"
  resource_name = "${var.service_name}-"
  pattern_type  = "PREFIXED"
  principal     = "User:${confluent_service_account.this.id}"
  host          = "*"
  operation     = "READ"
  permission    = "ALLOW"

  rest_endpoint = confluent_kafka_cluster.this.rest_endpoint
  credentials {
    key    = confluent_api_key.cluster_admin.id
    secret = confluent_api_key.cluster_admin.secret
  }
}
