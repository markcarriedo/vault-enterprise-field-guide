# Transit (encryption as a service)

## Goal

Vault as a cryptographic service, not a secrets store: an app sends plaintext, gets back
ciphertext, and never touches or sees the encryption key itself — the actual differentiator
versus just storing an app's own key in KV and letting it do encryption locally.

## Steps

1. Added a `transit` mount to `vault-config.yaml` (same generic `for_each` every other mount
   already uses — no new Terraform code needed for the mount itself) and one
   `vault_transit_secret_backend_key` (`terraform/vault-config/transit.tf`), named
   `inventory-service` to match the app-naming convention used everywhere else. `type =
   "aes256-gcm96"` set explicitly even though it's the default.
2. `exportable` and `deletion_allowed` left at their secure defaults (`false`) deliberately —
   `exportable` can never be turned back off once set, and `deletion_allowed = false` means
   `terraform destroy` on this resource fails loudly rather than silently discarding a key real
   data might depend on.
3. Extended the `inventory-service` policy with `update` on `transit/encrypt/inventory-service`
   and `transit/decrypt/inventory-service` only — deliberately no access to
   `transit/keys/inventory-service` (key metadata) or `transit/export/*/inventory-service` (raw
   key material). The app can use the key; it can never see it.
4. **Verified from the app's own identity, not root** — logged in via AWS auth on the demo
   client instance, encrypted real data, decrypted it back to the exact original plaintext,
   then confirmed both a key-metadata read and a key-export attempt came back a clean 403.
   Rotated the key as an operator afterward and confirmed a ciphertext from before rotation
   still decrypted correctly, while new encryptions moved to the new key version automatically
   — the actual value of a versioned key, not just "encryption happened."

## Gotchas

- The first Transit request after a fresh AWS-auth login can 412 with `required index state
  not present` when going through the internal load balancer — Vault Enterprise's
  read-after-write consistency check, since the login and the next request can land on
  different Raft nodes. Not a real failure; it resolves on retry.
- `vault read transit/keys/<name>` returns key metadata, never raw key bytes, regardless of
  policy access — actual export requires both `exportable = true` on the key (a one-way flag)
  and explicit access to `transit/export/<type>/<name>`, neither of which this build grants.

## References

- [Transit Secrets Engine (Vault docs)](https://developer.hashicorp.com/vault/docs/secrets/transit)
- [Test Transit encryption (runbook)](../../runbooks/transit-encryption.md)
