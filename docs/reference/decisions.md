# Decision Log

Short ADR-style entries for choices worth remembering the reasoning behind. Newest first.

Template:

```
## YYYY-MM-DD — Title

**Context:** why this came up
**Decision:** what we chose
**Alternatives considered:** what else we looked at
**Consequences:** what this means going forward
```

---

## 2026-09-09 — Sandbox account and region: HashiCorp sandbox, ap-southeast-2

**Context:** Needed a target AWS account/region to build in. Personal AWS profiles were an
option, but a HashiCorp Doormat-issued sandbox account is more appropriate — isolated from
personal infra, and expected to be disposable.

**Decision:** Build in the HashiCorp sandbox account (profile `hc-sandbox`, credentials local
only — not committed), region `ap-southeast-2`. Chosen for consistency with existing personal
profiles (both `ap-southeast-2`) and latency.

Note: STS session credentials are *not* region-locked — verified by successfully calling
`describe-vpcs` in three different regions with the same session. An initial region guess had
come from a hint embedded in the STS token's structure, not an actual restriction — worth
remembering next time a token needs a region assumption.

**Consequences:** All Terraform/AWS CLI work targets profile `hc-sandbox`, region
`ap-southeast-2`; credentials are short-lived (Doormat/STS) and will need periodic refresh.
Survey of that account/region found only the AWS-managed default VPC (3 public subnets, no
private subnets, no NAT gateways) and two AWS-managed KMS keys (Secrets Manager and Lambda
defaults) — neither usable for Vault. All four prerequisites start from scratch. Account IDs,
role ARNs, and other identifying infra details are deliberately kept out of this (public) repo.

---

## 2026-09-09 — Deploy via HashiCorp's official HVD module, not a hand-rolled Terraform config

**Context:** Need to stand up Vault Enterprise on AWS EC2. Could write our own Terraform from
scratch, or use HashiCorp's published [Validated Design module](https://github.com/hashicorp/terraform-aws-vault-enterprise-hvd)
(`hashicorp/vault-enterprise-hvd/aws`), which encodes HashiCorp's own recommended reference
architecture (ASG, NLB, IAM, Integrated Storage/Raft, KMS auto-unseal).

**Decision:** Use the HVD module. We're responsible for the prerequisite infrastructure it
expects (VPC/subnets, KMS key, Secrets Manager entries for license + TLS material) and for
supplying its required inputs; the module itself owns the Vault EC2/ASG/LB/IAM resources.

**Alternatives considered:** Hand-rolled Terraform — more control, but means re-deriving
HashiCorp's own reference architecture decisions (instance sizing, seal config, listener setup)
instead of starting from a maintained, HashiCorp-authored baseline.

**Consequences:** Our own Terraform is scoped to the four prerequisites, not the Vault
infrastructure itself. Any deviation from the module's supported inputs (see
[deployment customizations](https://github.com/hashicorp/terraform-aws-vault-enterprise-hvd/blob/main/docs/vault-deployment-customizations.md))
needs to go through its variables rather than editing generated resources directly.
