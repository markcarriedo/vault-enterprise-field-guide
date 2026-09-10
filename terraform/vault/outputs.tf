output "vault_cli_config" {
  description = "Environment variables to configure the Vault CLI"
  value       = module.vault.vault_cli_config
}

output "vault_load_balancer_name" {
  value = module.vault.vault_load_balancer_name
}

output "vault_load_balancer_security_group_id" {
  description = "Allow ingress on 8200 to this group to reach Vault through the LB"
  value       = module.vault.vault_load_balancer_security_group_id
}
