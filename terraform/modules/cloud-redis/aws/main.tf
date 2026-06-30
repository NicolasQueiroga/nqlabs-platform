locals {
  name           = "${var.service_name}-${var.environment}"
  num_clusters   = var.tier == "standard" ? 2 : 1
  is_ha          = var.tier == "standard"
  secret_path    = "${var.service_name}/${var.environment}/redis"
}

resource "random_password" "auth_token" {
  length  = 32
  special = false
}

resource "aws_elasticache_subnet_group" "this" {
  name       = local.name
  subnet_ids = var.subnet_ids

  tags = {
    Service     = var.service_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_security_group" "redis" {
  name        = "${local.name}-redis"
  description = "Allow Redis access for ${var.service_name} ${var.environment}"
  vpc_id      = var.vpc_id

  tags = {
    Service     = var.service_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_security_group_rule" "redis_ingress" {
  for_each = toset(var.allowed_cidr_blocks)

  type              = "ingress"
  from_port         = 6379
  to_port           = 6379
  protocol          = "tcp"
  cidr_blocks       = [each.value]
  security_group_id = aws_security_group.redis.id
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id = local.name
  description          = "${var.service_name} ${var.environment} Redis"

  node_type            = "cache.t4g.micro"
  num_cache_clusters   = local.num_clusters
  multi_az_enabled     = local.is_ha
  automatic_failover_enabled = local.is_ha

  engine_version             = "7.1"
  parameter_group_name       = "default.redis7"
  port                       = 6379
  subnet_group_name          = aws_elasticache_subnet_group.this.name
  security_group_ids         = [aws_security_group.redis.id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token                 = random_password.auth_token.result

  tags = {
    Service     = var.service_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_secretsmanager_secret" "redis" {
  name        = local.secret_path
  description = "Redis connection info for ${var.service_name} ${var.environment}"

  tags = {
    Service     = var.service_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_secretsmanager_secret_version" "redis" {
  secret_id = aws_secretsmanager_secret.redis.id

  secret_string = jsonencode({
    host       = aws_elasticache_replication_group.this.primary_endpoint_address
    port       = "6379"
    password   = random_password.auth_token.result
    redis_url  = "rediss://:${random_password.auth_token.result}@${aws_elasticache_replication_group.this.primary_endpoint_address}:6379"
  })
}

data "aws_iam_policy_document" "redis_secret_access" {
  statement {
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [aws_secretsmanager_secret.redis.arn]
  }
}

resource "aws_iam_policy" "redis_secret_access" {
  name        = "${local.name}-redis-secret-access"
  description = "Allow ${var.service_name} ${var.environment} to read Redis connection secret"
  policy      = data.aws_iam_policy_document.redis_secret_access.json

  tags = {
    Service     = var.service_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_iam_role_policy_attachment" "redis_secret_access" {
  role       = var.role_name
  policy_arn = aws_iam_policy.redis_secret_access.arn
}
