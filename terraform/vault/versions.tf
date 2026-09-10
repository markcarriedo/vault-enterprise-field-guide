terraform {
  required_version = ">= 1.11" # need 1.11+ for S3 native state locking (use_lockfile)

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    bucket       = "vault-enterprise-field-guide-tfstate-dc2565bd"
    key          = "vault/terraform.tfstate"
    region       = "ap-southeast-2"
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region
  # No `profile` - credentials come from the standard AWS SDK environment
  # variables, exported in the shell before running Terraform.
}

data "terraform_remote_state" "prerequisites" {
  backend = "s3"

  config = {
    bucket = "vault-enterprise-field-guide-tfstate-dc2565bd"
    key    = "prerequisites/terraform.tfstate"
    region = "ap-southeast-2"
  }
}
