# Vault as a certificate authority - the two-tier root/intermediate pattern
# HashiCorp's own PKI docs recommend, not a single mount issuing everything:
# the root only ever signs the intermediate's CSR, the intermediate does all
# real leaf-certificate issuance. Same reasoning as everywhere else in this
# build - minimize what any one thing is trusted to do. type = "internal" on
# both means the private keys are generated inside Vault and never leave it,
# same principle as Transit's exportable = false.

resource "vault_pki_secret_backend_root_cert" "root" {
  backend     = vault_mount.this["pki"].path
  type        = "internal"
  common_name = "Vault Enterprise Field Guide Root CA"
  ttl         = "87600h" # 10y
  key_type    = "rsa"
  key_bits    = 4096
}

resource "vault_pki_secret_backend_config_urls" "root" {
  backend = vault_mount.this["pki"].path
  issuing_certificates = [
    "https://vault.sandbox.internal:8200/v1/${vault_mount.this["pki"].path}/ca",
  ]
  crl_distribution_points = [
    "https://vault.sandbox.internal:8200/v1/${vault_mount.this["pki"].path}/crl",
  ]
}

resource "vault_pki_secret_backend_intermediate_cert_request" "intermediate" {
  backend     = vault_mount.this["pki_int"].path
  type        = "internal"
  common_name = "Vault Enterprise Field Guide Intermediate CA"
  key_type    = "rsa"
  key_bits    = 4096
}

resource "vault_pki_secret_backend_root_sign_intermediate" "intermediate" {
  backend     = vault_mount.this["pki"].path
  csr         = vault_pki_secret_backend_intermediate_cert_request.intermediate.csr
  common_name = "Vault Enterprise Field Guide Intermediate CA"
  ttl         = "43800h" # 5y
}

resource "vault_pki_secret_backend_intermediate_set_signed" "intermediate" {
  backend     = vault_mount.this["pki_int"].path
  certificate = vault_pki_secret_backend_root_sign_intermediate.intermediate.certificate
}

resource "vault_pki_secret_backend_config_urls" "intermediate" {
  backend = vault_mount.this["pki_int"].path
  issuing_certificates = [
    "https://vault.sandbox.internal:8200/v1/${vault_mount.this["pki_int"].path}/ca",
  ]
  crl_distribution_points = [
    "https://vault.sandbox.internal:8200/v1/${vault_mount.this["pki_int"].path}/crl",
  ]

  depends_on = [vault_pki_secret_backend_intermediate_set_signed.intermediate]
}

# Short TTLs are a deliberate demo choice, not a production recommendation -
# HashiCorp's own guidance suggests 30-90 days for real leaf certs. Using
# hours instead makes the actual point (certs issued on demand, short-lived
# by design) something this sandbox can demonstrate and verify directly
# rather than just assert.
resource "vault_pki_secret_backend_role" "inventory_service" {
  backend = vault_mount.this["pki_int"].path
  name    = "inventory-service"

  allowed_domains    = ["inventory-service.svc.internal"]
  allow_bare_domains = true
  allow_subdomains   = false

  # Vault's API always echoes TTLs back in seconds, regardless of what
  # duration-string form was submitted - using seconds directly here avoids
  # a perpetual "72h" != "259200" diff on every plan (same values: 259200s
  # = 72h, 86400s = 24h).
  max_ttl = "259200"
  ttl     = "86400"

  key_type = "rsa"
  key_bits = 2048

  depends_on = [vault_pki_secret_backend_intermediate_set_signed.intermediate]
}
