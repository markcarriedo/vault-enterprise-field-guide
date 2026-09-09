output "vpc_id" {
  value = module.vpc.vpc_id
}

output "vault_subnet_ids" {
  description = "Private subnet IDs - for the Vault nodes AND the internal-scheme load balancer"
  value       = module.vpc.private_subnets
}

output "lb_subnet_ids" {
  description = "Same private subnets - the module's load_balancing_scheme defaults to INTERNAL"
  value       = module.vpc.private_subnets
}

output "vault_seal_awskms_key_arn" {
  value = aws_kms_key.vault_unseal.arn
}

output "vault_license_secret_arn" {
  value = aws_secretsmanager_secret.vault_license.arn
}
