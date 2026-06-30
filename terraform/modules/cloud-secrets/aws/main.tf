locals {
  secrets_map = {
    for s in var.secrets : s.name => s
  }
}

data "aws_caller_identity" "current" {}

# One Secrets Manager secret per entry.
# Name pattern: <service>/<environment>/<name> — matches the Infisical key convention.
resource "aws_secretsmanager_secret" "this" {
  for_each = local.secrets_map

  name        = "${var.service_name}/${var.environment}/${each.key}"
  description = each.value.description != "" ? each.value.description : "Managed by Terraform for ${var.service_name}/${var.environment}."

  tags = {
    Service     = var.service_name
    Environment = var.environment
  }
}

# Inline IAM policy granting the workload role read access to every managed secret.
resource "aws_iam_policy" "secrets_read" {
  name        = "${var.service_name}-${var.environment}-secrets-read"
  description = "Grants GetSecretValue and DescribeSecret on ${var.service_name}/${var.environment} secrets."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadSecrets"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
        ]
        Resource = [
          for s in aws_secretsmanager_secret.this : s.arn
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "secrets_read" {
  role       = var.role_name
  policy_arn = aws_iam_policy.secrets_read.arn
}
