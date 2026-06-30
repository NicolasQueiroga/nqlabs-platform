output "bootstrap_brokers_sasl_scram" {
  description = "MSK bootstrap broker endpoints for SASL/SCRAM clients."
  value       = aws_msk_cluster.this.bootstrap_brokers_sasl_scram
}

output "cluster_arn" {
  description = "ARN of the MSK cluster."
  value       = aws_msk_cluster.this.arn
}

output "security_group_id" {
  description = "ID of the MSK security group."
  value       = aws_security_group.msk.id
}

output "sasl_secret_arns" {
  description = "Map of SASL username to Secrets Manager ARN."
  value       = { for k, v in aws_secretsmanager_secret.sasl_user : k => v.arn }
}
