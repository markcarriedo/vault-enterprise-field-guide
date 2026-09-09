# Planning & Prerequisites

## Goal

Deploy Vault Enterprise on AWS EC2 using HashiCorp's official
[Validated Design (HVD) module](https://github.com/hashicorp/terraform-aws-vault-enterprise-hvd)
(`hashicorp/vault-enterprise-hvd/aws` on the Terraform Registry), rather than hand-rolling the
ASG/load balancer/IAM setup ourselves. See [decision log](../reference/decisions.md) for why.

The module deploys Vault Enterprise with **Integrated Storage (Raft)** — no separate storage
backend to provision.

## Target environment

HashiCorp sandbox AWS account, region **ap-southeast-2**. Credentials are a Doormat-issued STS
session, exported as plain `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`/`AWS_SESSION_TOKEN`
environment variables for the duration of a session — no local AWS CLI profile, nothing
persisted to `~/.aws/credentials`. See [decision log](../reference/decisions.md) for how we
landed on this account/region and why no profile.

A survey of that account/region found only the AWS-managed default VPC (public subnets only,
no NAT gateways) and AWS-managed default KMS keys — nothing reusable. All four prerequisites
below are being built from scratch.

## Prerequisites

Before running the module, the following must already exist in AWS:

- [ ] **VPC** with at least 3 private subnets (distinct AZs) for the Vault nodes, plus subnets
      for the load balancer, and NAT Gateway(s) for outbound package/OS-patch access
- [ ] **Vault Enterprise license**, uploaded to AWS Secrets Manager (plaintext secret)
- [ ] **TLS certificate material** for the Vault FQDN — signed cert, private key, and CA bundle
      (each base64-encoded) — uploaded to AWS Secrets Manager as three separate plaintext secrets
- [ ] **AWS KMS key** (symmetric) dedicated to Vault auto-unseal — we need its ARN

## Deployment sequence

The full sequence, end to end. Terraform runs **locally only** — no CI/CD for this build (a
deliberate choice, not a placeholder to fill in later), so Terraform/Vault CLI installs and
cloud credentials are local-machine concerns, not pipeline concerns.

1. ~~Confirm target AWS account/region and re-authenticate AWS SSO~~ done
2. Create the certificate files (TLS cert, key, CA bundle for the Vault FQDN)
3. ~~Obtain the license file~~ done
4. ~~Download the Vault CLI~~ done (`v2.0.0`)
5. ~~Download the Terraform CLI~~ done (`v1.16.1`)
6. Bootstrap the Terraform state bucket (`terraform/bootstrap/` — see below); config written,
   plan reviewed (6 resources), **not yet applied**
7. Deploy the prerequisite resources (VPC, KMS key, Secrets Manager entries) — our own Terraform
   in `terraform/prerequisites/`; config written, plan reviewed (27 resources), **not yet
   applied**, and not yet pointed at the (not-yet-existing) state bucket as its backend —
   still using local state for now
8. Obtain the HVD module (`hashicorp/vault-enterprise-hvd/aws`)
9. ~~Configure cloud credentials~~ done (env vars, no profile — see decision log)
10. Initialize the Terraform workspace for the HVD module
11. Input variables (VPC/subnet IDs, KMS key ARN, Secrets Manager ARNs, FQDN) from step 7's output
12. `terraform plan`
13. `terraform apply`
14. Validate the cluster is up and reachable
15. Initialize the Vault cluster

### Terraform state (planned, not yet live)

Still local-only execution (no CI/CD), but state itself will live in **S3 with native locking**
(`use_lockfile = true`, no DynamoDB needed — GA since Terraform 1.11) rather than a local file:
durability and lock-safety without needing a pipeline. `terraform/bootstrap/` will create the
state bucket using local state itself (the standard chicken-and-egg exception for backend
bootstrapping) — once applied, `terraform/prerequisites/` gets a `backend "s3"` block added
pointing at that bucket. Until then, `prerequisites/` has no backend configured (defaults to
local) and hasn't been applied at all, so there's currently no state file anywhere for it.

## Gotchas

- STS session credentials are **not region-locked** — don't assume the region a token happens
  to work in first is the "correct" one; confirm explicitly.

## References

- [terraform-aws-vault-enterprise-hvd (GitHub)](https://github.com/hashicorp/terraform-aws-vault-enterprise-hvd)
- [hashicorp/vault-enterprise-hvd/aws (Terraform Registry)](https://registry.terraform.io/modules/hashicorp/vault-enterprise-hvd/aws/latest)
