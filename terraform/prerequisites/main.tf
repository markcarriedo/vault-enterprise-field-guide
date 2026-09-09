module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.7"

  name = "vault-enterprise"
  cidr = var.vpc_cidr

  azs = var.azs

  # Public subnets exist only to host the NAT Gateway(s) + IGW route - nothing
  # user-facing lives here. Vault nodes and the (internal-scheme) load
  # balancer both live in the private subnets.
  public_subnets  = [for i, az in var.azs : cidrsubnet(var.vpc_cidr, 8, i)]
  private_subnets = [for i, az in var.azs : cidrsubnet(var.vpc_cidr, 8, i + 10)]

  enable_nat_gateway = true
  single_nat_gateway = var.single_nat_gateway

  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Project = "vault-enterprise-field-guide"
  }
}

resource "aws_kms_key" "vault_unseal" {
  description             = "Vault Enterprise auto-unseal key"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Project = "vault-enterprise-field-guide"
  }
}

resource "aws_kms_alias" "vault_unseal" {
  name          = "alias/vault-enterprise-unseal"
  target_key_id = aws_kms_key.vault_unseal.key_id
}

resource "aws_secretsmanager_secret" "vault_license" {
  name = "vault-enterprise/license"

  tags = {
    Project = "vault-enterprise-field-guide"
  }
}

resource "aws_secretsmanager_secret_version" "vault_license" {
  secret_id     = aws_secretsmanager_secret.vault_license.id
  secret_string = file(var.vault_license_file)
}
