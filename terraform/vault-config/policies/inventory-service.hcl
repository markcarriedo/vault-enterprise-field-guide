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
