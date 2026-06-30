locals {
  k8s_sa_name = coalesce(var.k8s_sa_name, var.service_name)
  role_name   = "${var.service_name}-${var.environment}"
}

# Lookup the existing EKS OIDC provider created when the cluster was provisioned.
data "aws_iam_openid_connect_provider" "eks" {
  url = "https://${var.eks_oidc_provider_url}"
}

# --- IRSA trust policy --------------------------------------------------------

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.eks.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.eks_oidc_provider_url}:sub"
      values   = ["system:serviceaccount:${var.namespace}:${local.k8s_sa_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.eks_oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

# --- IAM role -----------------------------------------------------------------

resource "aws_iam_role" "this" {
  name               = local.role_name
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
  description        = "IRSA role for ${var.service_name} (${var.environment}), K8s SA ${var.namespace}/${local.k8s_sa_name}."

  tags = {
    managed-by  = "terraform"
    service     = var.service_name
    environment = var.environment
    namespace   = var.namespace
  }
}

# --- Policy attachments -------------------------------------------------------

resource "aws_iam_role_policy_attachment" "policies" {
  for_each = toset(var.policy_arns)

  role       = aws_iam_role.this.name
  policy_arn = each.value
}
