terraform {
  required_version = ">= 1.11" # need 1.11+ for S3 native state locking (use_lockfile)

  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.11"
    }
  }

  backend "s3" {
    bucket       = "vault-enterprise-field-guide-tfstate-dc2565bd"
    key          = "vault-config/terraform.tfstate"
    region       = "ap-southeast-2"
    use_lockfile = true
  }
}

# No explicit config - the provider reads VAULT_ADDR, VAULT_TOKEN, VAULT_CACERT, and
# VAULT_TLS_SERVER_NAME from the environment automatically (same as the CLI), consistent
# with how AWS credentials are handled everywhere else in this repo: nothing hardcoded,
# nothing persisted, supplied fresh per session. Requires the SSM tunnel from
# guide/05-operations.md to be running first.
provider "vault" {}
