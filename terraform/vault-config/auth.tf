# AWS auth method - lets an EC2 instance authenticate using its own IAM role
# identity (a signed STS GetCallerIdentity request) instead of a vended
# secret_id (AppRole) or the root token. See guide/04-configuration.md and
# the decision log for why AWS auth over AppRole in this build.
#
# The Vault nodes' own IAM role is looked up by name (not ARN) so the AWS
# account ID never appears literally in this file, only resolved
# dynamically at apply time. Used by dynamic-secrets.tf (Vault's own
# instance role is what assumes the target role there) - not by the auth
# method below, which binds to a separate, dedicated client identity
# instead (demo-client.tf) so a real app is never modeled as "the Vault
# server's own role."
data "aws_iam_role" "vault_node" {
  name = "vault-role"
}

resource "vault_auth_backend" "aws" {
  type = "aws"
}

resource "vault_aws_auth_backend_client" "this" {
  backend = vault_auth_backend.aws.path

  # No explicit access_key/secret_key - every argument here is optional.
  # Basic IAM-auth login just relays the client's already-signed
  # GetCallerIdentity request to STS; Vault doesn't sign anything itself.
}

# Which AWS IAM principal each app's aws_auth block (vault-config.yaml)
# trusts - kept as an explicit map here, not in the YAML, so a real trust
# binding is never hidden behind generic-looking config data. Add an entry
# here alongside a new app's aws_auth block.
locals {
  aws_auth_bound_principals = {
    inventory-service = aws_iam_role.inventory_service_instance.arn
  }
}

resource "vault_aws_auth_backend_role" "this" {
  for_each = { for name, app in local.config.apps : name => app.aws_auth if try(app.aws_auth, null) != null }

  backend   = vault_auth_backend.aws.path
  role      = each.key
  auth_type = "iam"

  bound_iam_principal_arns = [local.aws_auth_bound_principals[each.key]]
  token_policies           = [for p in each.value.token_policies : vault_policy.this[p].name]

  # Skips the extra iam:GetRole/iam:GetUser calls this would otherwise make
  # (matters if a deleted principal's ARN gets reused) - would need adding
  # IAM read permissions to the Vault node's own role just for that; not
  # worth it here since each bound ARN is already a stable, direct binding.
  resolve_aws_unique_ids = false
}
