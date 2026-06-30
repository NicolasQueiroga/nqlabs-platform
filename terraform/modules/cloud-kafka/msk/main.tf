locals {
  name             = "${var.service_name}-${var.environment}"
  broker_count     = var.tier == "standard" ? 3 : 1
  instance_type    = var.tier == "standard" ? "kafka.m5.large" : "kafka.t3.small"
}

resource "aws_security_group" "msk" {
  name        = "${local.name}-msk"
  description = "MSK cluster security group for ${var.service_name} ${var.environment}"
  vpc_id      = var.vpc_id

  tags = {
    Service     = var.service_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_security_group_rule" "msk_tls_ingress" {
  type              = "ingress"
  from_port         = 9096
  to_port           = 9096
  protocol          = "tcp"
  self              = true
  security_group_id = aws_security_group.msk.id
  description       = "Allow TLS+SASL Kafka within the security group"
}

resource "aws_msk_cluster" "this" {
  cluster_name           = local.name
  kafka_version          = var.kafka_version
  number_of_broker_nodes = local.broker_count

  broker_node_group_info {
    instance_type  = local.instance_type
    client_subnets = var.subnet_ids
    storage_info {
      ebs_storage_info {
        volume_size = 100
      }
    }
    security_groups = [aws_security_group.msk.id]
  }

  client_authentication {
    sasl {
      scram = true
    }
  }

  encryption_info {
    encryption_in_transit {
      client_broker = "TLS"
      in_cluster    = true
    }
  }

  open_monitoring {
    prometheus {
      jmx_exporter {
        enabled_in_broker = true
      }
      node_exporter {
        enabled_in_broker = true
      }
    }
  }

  tags = {
    Service     = var.service_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# Auto-generate passwords for each SASL user and store in Secrets Manager.
resource "random_password" "sasl" {
  for_each = toset(var.sasl_users)

  length  = 24
  special = false
}

resource "aws_secretsmanager_secret" "sasl_user" {
  for_each = toset(var.sasl_users)

  # MSK SASL/SCRAM secrets must be prefixed with AmazonMSK_.
  name        = "AmazonMSK_${local.name}_${each.value}"
  description = "SASL/SCRAM credentials for MSK user ${each.value} (${var.service_name} ${var.environment})"

  tags = {
    Service     = var.service_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_secretsmanager_secret_version" "sasl_user" {
  for_each = toset(var.sasl_users)

  secret_id = aws_secretsmanager_secret.sasl_user[each.value].id

  secret_string = jsonencode({
    username = each.value
    password = random_password.sasl[each.value].result
  })
}

resource "aws_msk_scram_secret_association" "this" {
  cluster_arn     = aws_msk_cluster.this.arn
  secret_arn_list = [for s in aws_secretsmanager_secret.sasl_user : s.arn]

  depends_on = [aws_secretsmanager_secret_version.sasl_user]
}
