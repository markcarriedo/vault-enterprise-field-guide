# AWS secrets engine - Vault hands out real, temporary AWS credentials on
# request instead of storing static ones (contrast with the KV v2 mount in
# main.tf). credential_type = "assumed_role": Vault assumes an existing IAM
# role via STS and returns the resulting temporary credentials - no IAM
# users ever created or deleted, unlike the iam_user credential type. See
# guide/04-configuration.md and the decision log for why assumed_role over
# iam_user here.
#
# The target role's own permissions are deliberately minimal
# (sts:GetCallerIdentity only) - this proves the mechanism (assume role,
# get temporary credentials, use them, Vault revokes the lease) without
# granting any real access. A real app would scope this role to whatever
# AWS API access it actually needs.
data "aws_iam_policy_document" "vault_dynamic_demo_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [data.aws_iam_role.vault_node.arn]
    }
  }
}

resource "aws_iam_role" "vault_dynamic_demo" {
  name               = "vault-dynamic-demo"
  assume_role_policy = data.aws_iam_policy_document.vault_dynamic_demo_trust.json
}

data "aws_iam_policy_document" "vault_dynamic_demo_permissions" {
  statement {
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"] # GetCallerIdentity doesn't target a specific resource
  }
}

resource "aws_iam_role_policy" "vault_dynamic_demo_permissions" {
  name   = "get-caller-identity-only"
  role   = aws_iam_role.vault_dynamic_demo.id
  policy = data.aws_iam_policy_document.vault_dynamic_demo_permissions.json
}

# Grants the Vault nodes' own IAM role (already referenced in auth.tf)
# permission to assume the role above - an inline policy added to that
# existing role from this state, distinct from anything the HVD module
# itself manages on it.
data "aws_iam_policy_document" "vault_node_assume_dynamic_demo" {
  statement {
    actions   = ["sts:AssumeRole"]
    resources = [aws_iam_role.vault_dynamic_demo.arn]
  }
}

resource "aws_iam_role_policy" "vault_node_assume_dynamic_demo" {
  name   = "assume-vault-dynamic-demo"
  role   = data.aws_iam_role.vault_node.name
  policy = data.aws_iam_policy_document.vault_node_assume_dynamic_demo.json
}

resource "vault_aws_secret_backend" "this" {
  region = "ap-southeast-2"

  # No access_key/secret_key - same credential pattern as everywhere else in
  # this repo: falls back to the AWS SDK default chain, which on a Vault
  # node resolves to its own instance role (now permitted, via the policy
  # above, to assume the demo role).
}

resource "vault_aws_secret_backend_role" "field_guide_app" {
  backend = vault_aws_secret_backend.this.path
  name    = "field-guide-app"

  credential_type = "assumed_role"
  role_arns       = [aws_iam_role.vault_dynamic_demo.arn]

  # Short-lived by default (AWS STS minimum) to actually demonstrate dynamic,
  # short-lived credentials rather than defaulting to a full hour.
  default_sts_ttl = 900
  max_sts_ttl     = 3600
}
