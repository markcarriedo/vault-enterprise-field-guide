variable "aws_region" {
  description = "AWS region for the Vault deployment"
  type        = string
  default     = "ap-southeast-2"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Availability zones to spread subnets across"
  type        = list(string)
  default     = ["ap-southeast-2a", "ap-southeast-2b", "ap-southeast-2c"]
}

variable "single_nat_gateway" {
  description = "Use one NAT Gateway for all private subnets instead of one per AZ - cheaper, less resilient. Fine for a sandbox."
  type        = bool
  default     = true
}

variable "vault_license_file" {
  description = "Local path to the Vault Enterprise license file (.hclic) - never committed to git"
  type        = string
  default     = "/Users/mark/Downloads/vault.hclic"
}
