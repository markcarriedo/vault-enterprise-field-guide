# PKI (Vault as a certificate authority)

## Goal

Vault issuing short-lived certificates on demand, not storing pre-existing ones — the actual
differentiator over dropping a long-lived cert in KV. Built as the two-tier root/intermediate
pattern HashiCorp's own PKI docs recommend, not a single mount doing everything.

## Steps

1. Added two mounts (`pki`, `pki_int`) through the existing generic YAML/`for_each` pattern —
   extended with one new field, `max_lease_ttl_seconds`, since PKI's default mount TTL (32
   days) is nowhere near long enough for a root cert meant to last years.
   `terraform/vault-config/pki.tf` then chains five PKI-specific resources: generate the root
   (`vault_pki_secret_backend_root_cert`, `type = "internal"` — the private key never leaves
   Vault, same principle as Transit's `exportable = false`), request an intermediate CSR
   (`vault_pki_secret_backend_intermediate_cert_request`), sign it with the root
   (`vault_pki_secret_backend_root_sign_intermediate`), install the signed cert back onto the
   intermediate (`vault_pki_secret_backend_intermediate_set_signed`), then configure
   issuing/CRL URLs for both mounts.
2. The root **only ever signs the intermediate** — it has no role of its own and never issues a
   leaf certificate directly. All real issuance goes through `pki_int` and one role,
   `inventory-service`, scoped to `allowed_domains = ["inventory-service.svc.internal"]`,
   `allow_bare_domains = true`, `allow_subdomains = false` — one app, one exact identity, same
   "narrow by default" pattern as every other role in this build.
3. Role TTLs (`max_ttl`/`ttl`) are set as second-based strings (`"259200"`/`"86400"`), not
   `"72h"`/`"24h"` — Vault's API always echoes TTLs back in seconds regardless of the input
   format, and using the duration-string form here produced a perpetual, harmless-but-annoying
   diff on every `terraform plan`. Same values, just matching what state actually stores.
   Extended the `inventory-service` policy with `create`/`update` on
   `pki_int/issue/inventory-service` only.
4. **Verified from the app's own identity, not root** — requested a cert as
   `inventory-service`, then verified the full chain (leaf → intermediate → root) with `openssl
   verify` against the real PKI root CA — not the cluster's own, unrelated TLS CA, a mistake
   made once while building this and worth flagging as a real gotcha. Confirmed the app was
   denied revoking its own cert, reading the CA config, and listing all issued certs (all a
   clean 403), then revoked the cert as an operator and confirmed the serial actually landed on
   the CRL.

## Gotchas

- This build has two entirely separate CAs — the cluster's own TLS CA (trusts Vault's HTTPS
  listener) and the PKI-issued root CA (trusts certificates Vault issues). Verifying an issued
  cert's chain against the wrong one fails with "unable to get local issuer certificate."
- PKI mounts default to a 32-day max lease TTL — nowhere near enough for a root cert meant to
  last years. Set `max_lease_ttl_seconds` explicitly on the mount, well above the
  root/intermediate certs' own TTLs, or generating either will silently get truncated.
- PKI role `ttl`/`max_ttl` should be set as second-based strings, not duration strings like
  `"72h"` — Vault's API always echoes TTLs back in seconds, so a duration-string input produces
  a perpetual (harmless) diff on every `terraform plan` against the same actual value.

## References

- [PKI Secrets Engine (Vault docs)](https://developer.hashicorp.com/vault/docs/secrets/pki)
- [PKI considerations (Vault docs)](https://developer.hashicorp.com/vault/docs/secrets/pki/considerations)
- [Test PKI certificate issuance (runbook)](../../runbooks/pki-certificates.md)
