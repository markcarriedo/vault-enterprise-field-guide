terraform {
  required_version = ">= 1.11" # need 1.11+ for S3 native state locking (use_lockfile)

  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.11"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
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

# Used to look up the Vault nodes' own IAM role by name (auth.tf,
# dynamic-secrets.tf) and to run the AWS-auth demo client instance
# (demo-client.tf) - same credential pattern as every other AWS provider
# block in this repo: no profile, no keys, just the env vars exported for
# the session.
provider "aws" {
  region = "ap-southeast-2"
}

# VPC/subnet IDs for the demo client instance - read from prerequisites'
# state rather than re-declared here, same pattern terraform/vault uses.
data "terraform_remote_state" "prerequisites" {
  backend = "s3"

  config = {
    bucket = "vault-enterprise-field-guide-tfstate-dc2565bd"
    key    = "prerequisites/terraform.tfstate"
    region = "ap-southeast-2"
  }
}
