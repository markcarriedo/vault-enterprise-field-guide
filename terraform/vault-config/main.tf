locals {
  config = yamldecode(file("${path.module}/vault-config.yaml"))
}

resource "vault_mount" "this" {
  for_each = local.config.mounts

  path        = each.key
  type        = each.value.type
  description = try(each.value.description, null)
  options     = try(each.value.options, null)
}

resource "vault_policy" "this" {
  for_each = local.config.policies

  name   = each.key
  policy = file("${path.module}/policies/${each.value.policy_file}")
}
