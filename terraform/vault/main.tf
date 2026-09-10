module "vault" {
  source  = "hashicorp/vault-enterprise-hvd/aws"
  version = "~> 0.4"

  net_vpc_id           = data.terraform_remote_state.prerequisites.outputs.vpc_id
  net_vault_subnet_ids = data.terraform_remote_state.prerequisites.outputs.vault_subnet_ids
  net_lb_subnet_ids    = data.terraform_remote_state.prerequisites.outputs.lb_subnet_ids

  sm_vault_license_arn      = data.terraform_remote_state.prerequisites.outputs.vault_license_secret_arn
  sm_vault_tls_cert_arn     = data.terraform_remote_state.prerequisites.outputs.vault_tls_cert_secret_arn
  sm_vault_tls_cert_key_arn = data.terraform_remote_state.prerequisites.outputs.vault_tls_key_secret_arn
  sm_vault_tls_ca_bundle    = data.terraform_remote_state.prerequisites.outputs.vault_tls_ca_bundle_secret_arn

  vault_fqdn                = data.terraform_remote_state.prerequisites.outputs.vault_fqdn
  vault_seal_awskms_key_arn = data.terraform_remote_state.prerequisites.outputs.vault_seal_awskms_key_arn

  # Module default (1.17.3+ent) crash-looped against our license - "invalid
  # module: platform-standard" (a real entitlement mismatch, not a Terraform
  # bug). Pinning to 2.1.0+ent instead.
  vault_version = "2.1.0+ent"

  # load_balancing_scheme stays the module default (INTERNAL) - access is via
  # SSM port-forwarding from inside the VPC (see decision log), never real
  # internet traffic, so ingress is restricted to in-VPC CIDRs only.
  net_ingress_lb_cidr_blocks = [var.vpc_cidr]

  # No bastion host - SSM lets us tunnel straight to a Vault node.
  ec2_allow_ssm = true

  asg_node_count = var.asg_node_count

  create_route53_vault_dns_record      = true
  route53_vault_hosted_zone_name       = data.terraform_remote_state.prerequisites.outputs.route53_hosted_zone_name
  route53_vault_hosted_zone_is_private = true
}
