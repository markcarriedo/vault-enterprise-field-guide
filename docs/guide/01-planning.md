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
below have since been built from scratch.

## Prerequisites

Before running the module, the following must already exist in AWS:

- [x] **VPC** with at least 3 private subnets (distinct AZs) for the Vault nodes, plus subnets
      for the load balancer, and NAT Gateway(s) for outbound package/OS-patch access
- [x] **Vault Enterprise license**, uploaded to AWS Secrets Manager (plaintext secret)
- [x] **TLS certificate material** for the Vault FQDN — signed cert, private key, and CA bundle
      (each base64-encoded) — uploaded to AWS Secrets Manager as three separate plaintext secrets
- [x] **AWS KMS key** (symmetric) dedicated to Vault auto-unseal — we need its ARN

All four applied via `terraform/prerequisites` (39 resources total across two applies). ARNs/IDs
deliberately not recorded here (public repo) — run `terraform output` locally to get them when
wiring up the HVD module.

FQDN is `vault.sandbox.internal`, resolved by a **Route53 private hosted zone** associated with
the VPC — no real domain needed, since private zones don't validate ownership (that only
matters for public zones and publicly-trusted certs). Cert is a self-signed CA + leaf,
generated declaratively via the `tls` Terraform provider rather than a separate `openssl`
script — see [decision log](../reference/decisions.md) for the reasoning and the enterprise-vs-
sandbox tradeoff.

## Deployment sequence

The full sequence, end to end. Terraform runs **locally only** — no CI/CD for this build (a
deliberate choice, not a placeholder to fill in later), so Terraform/Vault CLI installs and
cloud credentials are local-machine concerns, not pipeline concerns.

1. ~~Confirm target AWS account/region and re-authenticate AWS SSO~~ done
2. ~~Create the certificate files~~ done — self-signed CA + leaf cert for `vault.sandbox.internal`,
   generated via the `tls` provider, plus a Route53 private hosted zone
3. ~~Obtain the license file~~ done
4. ~~Download the Vault CLI~~ done (`v2.0.0`)
5. ~~Download the Terraform CLI~~ done (`v1.16.1`)
6. ~~Bootstrap the Terraform state bucket~~ done (`terraform/bootstrap/`)
7. ~~Deploy the prerequisite resources~~ done — VPC, KMS key, license secret, TLS secrets, and
   the private zone (39 resources total) applied via `terraform/prerequisites/`, state in S3
8. ~~Obtain the HVD module~~ done — `hashicorp/vault-enterprise-hvd/aws` `~> 0.4`, in
   `terraform/vault/`
9. ~~Configure cloud credentials~~ done (env vars, no profile — see decision log)
10. ~~Initialize the Terraform workspace~~ done
11. ~~Input variables~~ done — via `data.terraform_remote_state` reading step 7's outputs
    directly, no manual ARN copying; 3 nodes (module default is 6), SSM access instead of a
    bastion, LB ingress restricted to the VPC CIDR
12. ~~`terraform plan`~~ done — 19 resources, reviewed
13. ~~`terraform apply`~~ done — hit a real license/version mismatch on first apply, fixed by
    pinning `vault_version`, see decision log
14. ~~Validate the cluster is up and reachable~~ done — all 3 nodes healthy in the target
    group, confirmed via SSM: `active`, `2.1.0+ent`, `awskms` seal, HA enabled, raft storage,
    correctly `Initialized: false` / `Sealed: true`
15. Initialize the Vault cluster

### Terraform state

Still local-only execution (no CI/CD), but state itself lives in **S3 with native locking**
(`use_lockfile = true`, no DynamoDB needed — GA since Terraform 1.11) rather than a local file:
durability and lock-safety without needing a pipeline. `terraform/bootstrap/` created the state
bucket using local state itself (the standard chicken-and-egg exception for backend
bootstrapping, applied once and rarely touched again); `terraform/prerequisites/` now has a
`backend "s3"` block pointing at that bucket, confirmed working via `terraform init` + `plan`
(no local `terraform.tfstate` anywhere for it, bucket empty until the first `apply`).

## Gotchas

- STS session credentials are **not region-locked** — don't assume the region a token happens
  to work in first is the "correct" one; confirm explicitly.
- The HVD module's default `vault_version` (`1.17.3+ent`) didn't match our license's
  entitlements — nodes crash-looped on `invalid module: "platform-standard"`. Not obvious from
  Terraform (it applies cleanly either way); only shows up once you check `systemctl status
  vault`/`journalctl -u vault` on an actual node. See decision log.
- The module's Route53 zone lookup defaults to public-zone semantics —
  `route53_vault_hosted_zone_is_private = true` is required for a private zone, or you get
  "no matching Route 53 Hosted Zone found" even though the zone clearly exists.
- Updating the launch template (e.g. to change `vault_version`) doesn't touch already-running
  ASG instances — needs a separate `aws autoscaling start-instance-refresh` to actually roll
  them.

## References

- [terraform-aws-vault-enterprise-hvd (GitHub)](https://github.com/hashicorp/terraform-aws-vault-enterprise-hvd)
- [hashicorp/vault-enterprise-hvd/aws (Terraform Registry)](https://registry.terraform.io/modules/hashicorp/vault-enterprise-hvd/aws/latest)
