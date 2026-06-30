output "role_arn" {
  description = "ARN of the IAM role. Set as the eks.amazonaws.com/role-arn annotation on the Kubernetes ServiceAccount."
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "Name of the IAM role."
  value       = aws_iam_role.this.name
}
