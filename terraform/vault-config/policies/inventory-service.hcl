# Read-only access to this app's own secrets - the pattern an app/service
# would actually use, instead of the root token.
path "secret/data/inventory-service/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/inventory-service/*" {
  capabilities = ["list"]
}

# Dynamic AWS credentials, scoped to this app's own role in the aws/
# secrets engine - see guide/04-configuration.md.
path "aws/creds/inventory-service" {
  capabilities = ["read"]
}

# Encrypt/decrypt only - deliberately no access to transit/keys/inventory-service
# (key metadata) or transit/export/*/inventory-service (raw key material). The
# app proves it can use the key without ever being able to see it.
path "transit/encrypt/inventory-service" {
  capabilities = ["update"]
}

path "transit/decrypt/inventory-service" {
  capabilities = ["update"]
}

# Issue certs from this app's own PKI role only - never touches the root
# (pki/) or intermediate (pki_int/) mounts' own management paths (sign-verbatim,
# CA info, revoke-with-key, etc.), just the narrow issue/<role> endpoint.
path "pki_int/issue/inventory-service" {
  capabilities = ["create", "update"]
}
