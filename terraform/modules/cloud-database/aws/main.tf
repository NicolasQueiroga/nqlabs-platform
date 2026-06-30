locals {
  name = "${var.service_name}-${var.environment}"

  instance_class_map = {
    small    = "db.t4g.micro"
    standard = "db.t4g.medium"
    large    = "db.t4g.large"
  }

  instance_class = local.instance_class_map[var.tier]
  multi_az       = var.tier != "small"
  db_name        = replace(var.service_name, "-", "_")
  db_user        = replace(var.service_name, "-", "_")
  secret_path    = "${var.service_name}/${var.environment}/database"
}

resource "random_password" "db" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_db_subnet_group" "main" {
  name        = local.name
  description = "DB subnet group for ${var.service_name} ${var.environment}"
  subnet_ids  = var.subnet_ids

  tags = {
    Name        = local.name
    Service     = var.service_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_security_group" "rds" {
  name        = "${local.name}-rds"
  description = "Allow PostgreSQL access to ${var.service_name} RDS in ${var.environment}"
  vpc_id      = var.vpc_id

  tags = {
    Name        = "${local.name}-rds"
    Service     = var.service_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_security_group_rule" "postgres_ingress" {
  type              = "ingress"
  from_port         = 5432
  to_port           = 5432
  protocol          = "tcp"
  cidr_blocks       = var.allowed_cidr_blocks
  security_group_id = aws_security_group.rds.id
  description       = "PostgreSQL from allowed CIDRs"
}

resource "aws_security_group_rule" "egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.rds.id
  description       = "Allow all egress"
}

resource "aws_db_instance" "main" {
  identifier = local.name

  engine               = "postgres"
  engine_version       = "17"
  instance_class       = local.instance_class
  db_name              = local.db_name
  username             = local.db_user
  password             = random_password.db.result
  parameter_group_name = "default.postgres17"

  allocated_storage     = 20
  max_allocated_storage = 100
  storage_encrypted     = true
  storage_type          = "gp3"

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  multi_az                = local.multi_az
  backup_retention_period = 7
  backup_window           = "02:00-03:00"
  maintenance_window      = "Mon:03:00-Mon:04:00"

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = !var.deletion_protection
  final_snapshot_identifier = var.deletion_protection ? "${local.name}-final" : null

  tags = {
    Name        = local.name
    Service     = var.service_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# Store connection details in Secrets Manager.
resource "aws_secretsmanager_secret" "connection" {
  name        = local.secret_path
  description = "Database connection details for ${var.service_name} (${var.environment})"

  tags = {
    Service     = var.service_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_secretsmanager_secret_version" "connection" {
  secret_id = aws_secretsmanager_secret.connection.id
  secret_string = jsonencode({
    username       = local.db_user
    password       = random_password.db.result
    host           = aws_db_instance.main.address
    port           = aws_db_instance.main.port
    database       = local.db_name
    connection_url = "postgresql://${local.db_user}:${random_password.db.result}@${aws_db_instance.main.endpoint}/${local.db_name}"
  })
}

# Grant the service IAM role access to read the secret.
data "aws_iam_policy_document" "secret_access" {
  statement {
    sid    = "SecretAccess"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [aws_secretsmanager_secret.connection.arn]
  }
}

resource "aws_iam_policy" "secret_access" {
  name        = "${local.name}-db-secret-access"
  description = "Allow ${var.service_name} ${var.environment} to read database secret"
  policy      = data.aws_iam_policy_document.secret_access.json

  tags = {
    Service     = var.service_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_iam_role_policy_attachment" "secret_access" {
  role       = var.role_name
  policy_arn = aws_iam_policy.secret_access.arn
}
