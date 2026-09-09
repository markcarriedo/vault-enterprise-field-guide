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

## 2026-09-09 — Retire the journal in favor of a git-cliff changelog

**Context:** Had been hand-writing `docs/journal/` as a dated, narrative log. Wanted a
changelog without adopting full `semantic-release` (no package/release cadence here — this
is a continuously-updated docs site, not a versioned artifact). Considered `git-cliff` purely
as a supplementary changelog alongside the journal, since git-cliff only knows what's in
commit messages — no reasoning, unless it's written there.

**Decision:** Adopt [Conventional Commits](https://www.conventionalcommits.org) for every
commit going forward, write reasoning into the commit **body** (not just a one-line summary),
and configure `git-cliff` (`cliff.toml`) to render that body in the generated changelog —
closing the gap that made journal narrative seem necessary in the first place. Retire the
journal entirely; `docs/changelog.md` (a snippet-include of the generated root `CHANGELOG.md`)
takes over its role in the site nav.

**Alternatives considered:** Keeping both (journal for reasoning, git-cliff for a terse
commit list) — rejected as redundant once reasoning lives in commit bodies instead.
Rewriting existing commit history to retrofit Conventional Commits — rejected; this repo is
public and already pushed, so rewriting published history isn't worth it. Existing commits
are kept as-is and fall into an "Other" bucket in the changelog (`filter_unconventional =
false` in `cliff.toml`) rather than being dropped or rewritten.

**Consequences:** Every future commit needs a `type(scope): summary` line and, where the
change isn't self-explanatory, a body paragraph explaining why. `CHANGELOG.md` is generated
(via `git-cliff`), not hand-written, and is gitignored — regenerate with `git-cliff -o
CHANGELOG.md` before building the site locally; CI regenerates it on every deploy. Work that
produces no commit at all (pure investigation, a decision reached through discussion) still
has no home unless it's folded into the next related commit's body.

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
