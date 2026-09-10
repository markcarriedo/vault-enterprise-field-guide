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

output "vault_fqdn" {
  value = var.vault_fqdn
}

output "route53_hosted_zone_name" {
  value = aws_route53_zone.vault_private.name
}

output "vault_tls_cert_secret_arn" {
  value = aws_secretsmanager_secret.vault_tls_cert.arn
}

output "vault_tls_key_secret_arn" {
  value = aws_secretsmanager_secret.vault_tls_key.arn
}

output "vault_tls_ca_bundle_secret_arn" {
  value = aws_secretsmanager_secret.vault_tls_ca_bundle.arn
}
