# AWS auth method - lets an EC2 instance authenticate using its own IAM role
# identity (a signed STS GetCallerIdentity request) instead of a vended
# secret_id (AppRole) or the root token. See guide/04-configuration.md and
# the decision log for why AWS auth over AppRole in this build.
#
# There's no separate "app" instance in this sandbox - the client proving
# the pattern end-to-end is one of the Vault nodes' own EC2 instance roles,
# looked up by name (not ARN) so the AWS account ID never appears literally
# in this file, only resolved dynamically at apply time.
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

resource "vault_aws_auth_backend_role" "field_guide_app" {
  backend   = vault_auth_backend.aws.path
  role      = "field-guide-app"
  auth_type = "iam"

  bound_iam_principal_arns = [data.aws_iam_role.vault_node.arn]
  token_policies           = [vault_policy.this["field-guide-app"].name]

  # Skips the extra iam:GetRole/iam:GetUser calls this would otherwise make
  # (matters if a deleted principal's ARN gets reused) - would need adding
  # IAM read permissions to the Vault node's own role just for that; not
  # worth it here since the bound ARN is already a stable, direct binding.
  resolve_aws_unique_ids = false
}
