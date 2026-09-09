# Planning & Prerequisites

## Goal

Deploy Vault Enterprise on AWS EC2 using HashiCorp's official
[Validated Design (HVD) module](https://github.com/hashicorp/terraform-aws-vault-enterprise-hvd)
(`hashicorp/vault-enterprise-hvd/aws` on the Terraform Registry), rather than hand-rolling the
ASG/load balancer/IAM setup ourselves. See [decision log](../reference/decisions.md) for why.

The module deploys Vault Enterprise with **Integrated Storage (Raft)** — no separate storage
backend to provision.

## Prerequisites

Before running the module, the following must already exist in AWS:

- [ ] **VPC** with at least 3 private subnets (distinct AZs) for the Vault nodes, plus subnets
      for the load balancer, and NAT Gateway(s) for outbound package/OS-patch access
- [ ] **Vault Enterprise license**, uploaded to AWS Secrets Manager (plaintext secret)
- [ ] **TLS certificate material** for the Vault FQDN — signed cert, private key, and CA bundle
      (each base64-encoded) — uploaded to AWS Secrets Manager as three separate plaintext secrets
- [ ] **AWS KMS key** (symmetric) dedicated to Vault auto-unseal — we need its ARN

## Steps

1. Confirm target AWS account/region and re-authenticate AWS SSO
2. Provision the VPC (or identify an existing one that meets the subnet requirement)
3. Create the KMS key for auto-unseal
4. Obtain/prepare the Vault Enterprise license and TLS certificate material, upload both to
   Secrets Manager
5. Run the HVD module against the above

## Gotchas

## References

- [terraform-aws-vault-enterprise-hvd (GitHub)](https://github.com/hashicorp/terraform-aws-vault-enterprise-hvd)
- [hashicorp/vault-enterprise-hvd/aws (Terraform Registry)](https://registry.terraform.io/modules/hashicorp/vault-enterprise-hvd/aws/latest)
