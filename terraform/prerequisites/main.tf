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

# Private hosted zone - resolves var.vault_fqdn only within this VPC. No real
# domain ownership needed (that's only required for public zones and
# public-CA cert validation, neither of which apply here). The HVD module
# creates the actual alias record for the LB when create_route53_vault_dns_record
# is set, using this zone by name.
resource "aws_route53_zone" "vault_private" {
  name = var.vault_fqdn

  vpc {
    vpc_id = module.vpc.vpc_id
  }

  tags = {
    Project = "vault-enterprise-field-guide"
  }
}

# Self-signed CA + leaf cert for var.vault_fqdn, generated declaratively (no
# separate openssl script) so it lives in state alongside everything else.
# A real enterprise deployment would use a trusted internal/private CA
# instead - this is the sandbox-pragmatic stand-in for that same pattern.
resource "tls_private_key" "ca" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_self_signed_cert" "ca" {
  private_key_pem = tls_private_key.ca.private_key_pem

  subject {
    common_name  = "Vault Enterprise Field Guide Sandbox CA"
    organization = "vault-enterprise-field-guide"
  }

  validity_period_hours = 24 * 365 * 5 # 5y - sandbox, no rotation process (yet)
  is_ca_certificate     = true

  allowed_uses = [
    "cert_signing",
    "crl_signing",
    "digital_signature",
    "key_encipherment",
  ]
}

resource "tls_private_key" "vault_leaf" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "vault_leaf" {
  private_key_pem = tls_private_key.vault_leaf.private_key_pem
  dns_names       = [var.vault_fqdn]

  subject {
    common_name = var.vault_fqdn
  }
}

resource "tls_locally_signed_cert" "vault_leaf" {
  cert_request_pem  = tls_cert_request.vault_leaf.cert_request_pem
  ca_private_key_pem = tls_private_key.ca.private_key_pem
  ca_cert_pem       = tls_self_signed_cert.ca.cert_pem

  validity_period_hours = 24 * 365 * 2 # 2y

  allowed_uses = [
    "digital_signature",
    "key_encipherment",
    "server_auth",
  ]
}

# Module requires each of these base64-encoded, stored as plaintext secrets.
resource "aws_secretsmanager_secret" "vault_tls_cert" {
  name = "vault-enterprise/tls-cert"

  tags = {
    Project = "vault-enterprise-field-guide"
  }
}

resource "aws_secretsmanager_secret_version" "vault_tls_cert" {
  secret_id     = aws_secretsmanager_secret.vault_tls_cert.id
  secret_string = base64encode(tls_locally_signed_cert.vault_leaf.cert_pem)
}

resource "aws_secretsmanager_secret" "vault_tls_key" {
  name = "vault-enterprise/tls-key"

  tags = {
    Project = "vault-enterprise-field-guide"
  }
}

resource "aws_secretsmanager_secret_version" "vault_tls_key" {
  secret_id     = aws_secretsmanager_secret.vault_tls_key.id
  secret_string = base64encode(tls_private_key.vault_leaf.private_key_pem)
}

resource "aws_secretsmanager_secret" "vault_tls_ca_bundle" {
  name = "vault-enterprise/tls-ca-bundle"

  tags = {
    Project = "vault-enterprise-field-guide"
  }
}

resource "aws_secretsmanager_secret_version" "vault_tls_ca_bundle" {
  secret_id     = aws_secretsmanager_secret.vault_tls_ca_bundle.id
  secret_string = base64encode(tls_self_signed_cert.ca.cert_pem)
}
