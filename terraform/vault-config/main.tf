resource "vault_mount" "secret" {
  path        = "secret"
  type        = "kv"
  description = "Static secrets (KV v2) - see guide/04-configuration.md"

  options = {
    version = "2"
  }
}

resource "vault_policy" "field_guide_app" {
  name   = "field-guide-app"
  policy = file("${path.module}/policies/field-guide-app.hcl")
}
