# One key per app, same naming convention as the KV path and AWS auth role -
# see guide/04-configuration.md for why an app only ever gets encrypt/decrypt
# capabilities (policies/inventory-service.hcl), never read/export on the key
# itself. exportable and deletion_allowed are both left at their secure
# defaults (false) - deliberately, not an oversight: exportable can never be
# turned back off once set, and deletion_allowed=false means `terraform
# destroy` on this resource fails loudly instead of silently discarding a key
# that may have real encrypted data depending on it.
resource "vault_transit_secret_backend_key" "inventory_service" {
  backend = vault_mount.this["transit"].path
  name    = "inventory-service"
  type    = "aes256-gcm96"
}
