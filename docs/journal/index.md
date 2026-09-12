# Journal

Dated field notes from the build, in the order things happened. Newest entries at the top.
For the "why" behind a specific choice, see the [decision log](../reference/decisions.md); for
the mechanical commit-by-commit record, see [`CHANGELOG.md`](https://github.com/markcarriedo/vault-enterprise-field-guide/blob/main/CHANGELOG.md)
at the repo root. This page sits between the two: the story, at a coarser grain than either.

---

## 2026-09-12 — A real client instance, a nicer YAML shape, and a proper name

Closed a gap flagged back when AWS auth first went in: the "client" proving the pattern was
the Vault nodes' own IAM role, which only ever made sense as a stopgap - a real app shouldn't
authenticate to Vault as the Vault server itself. Added a dedicated, minimal EC2 instance
(`terraform/vault-config/demo-client.tf`) whose only job is to *be* a distinct identity - no
AWS permissions beyond SSM access to reach it. Considered skipping the EC2 instance entirely
(assume a role locally instead, zero new infrastructure) but went with the real instance
anyway, since it demonstrates the pattern real EC2-based Vault clients actually use.

That surfaced a genuine Terraform footgun: renaming the instance's IAM role, instance
profile, and security group (all real name changes, not just relabeling) forces AWS to
recreate them - fine - but the *instance* referencing them doesn't need to be destroyed too,
only updated in place. The first two apply attempts didn't realize that and got stuck for
25+ minutes in a dependency-violation loop (Terraform trying to delete the old security group
while the instance was still silently attached to it). Fixed by targeting the instance update
on its own first (`-target=aws_instance...`), confirming via `aws ec2 describe-instances` that
it had actually moved to the new security group, then letting a normal apply clean up what was
left - which finished in one second once nothing was still attached.

While rebuilding the client identity, also renamed the example app from `field-guide-app` to
`inventory-service` - a placeholder name that had just stuck since the very first KV path -
and restructured `vault-config.yaml`: `aws_auth_roles` and `aws_secret_roles` used to be
separate top-level maps keyed by the same app name; nested them under one `apps` map instead,
each entry grouping its policy and role bindings together. Which AWS IAM principal a role
trusts stayed deliberately out of the YAML either way - that's still an explicit map next to
the real IAM resources, not something to hide behind a config value.

Moved the actual KV secret data across paths by hand (`vault kv put` at the new path, `vault
kv metadata delete` at the old one) since Terraform only manages the mount, not individual
key-value entries. Re-ran the full auth + dynamic-secrets proof afterward from the new
instance - which surfaced one more thing to fix along the way: `VAULT_ADDR=127.0.0.1:8200`
only makes sense on an actual Vault node with a local Vault process to forward to; a separate
client instance needs the cluster's real in-VPC address instead.

## 2026-09-11 — Dynamic secrets, and a real gotcha caught by actually testing revocation

First dynamic secret: the AWS secrets engine, `credential_type = "assumed_role"` rather than
`iam_user` - one small IAM role trusted to assume, permissioned down to
`sts:GetCallerIdentity` only, instead of handing Vault's own role broad IAM-user-management
permissions for a sandbox demo. Extended `inventory-service` (the same policy, not a new one)
with read access to `aws/creds/inventory-service`, so one app identity now spans KV v2, AWS
auth, and dynamic AWS credentials.

Verified the way this whole build insists on: logged in via AWS auth, read the dynamic
credentials, then actually called AWS STS with them and got back the assumed role's own
identity - not Vault's, not a guess that the read "worked."

The real find came from pushing one step further than "it works": revoked the lease with the
root token, confirmed Vault said `Success!`, then tried the exact same credentials again.
They still worked. Turns out AWS STS has no general way to invalidate an already-issued
session before its own expiry - confirmed against AWS's own IAM docs, which describe a
deny-policy-by-session-start-time workaround as the real mechanism, not anything Vault
applies automatically. So for `assumed_role` (and `federation_token`), "revoke" only ever
means "Vault stops tracking this" - the credential itself is still live until its TTL runs
out. `iam_user` doesn't have this gap, since deleting a real IAM user kills its key outright.
Worth knowing before reaching for `assumed_role` with anything that isn't a 15-minute demo.

## 2026-09-10 — Off the root token: AWS auth method, not AppRole

Finally closed a gap that had been sitting there since the first KV v2 test: every real
operation this whole build had used the root token. Looked at AppRole first, since it's the
usual answer - talked through how to vend its `secret_id` safely, and the honest answer was
"there isn't a good one here," since a `secret_id` needs a trusted distributor and this repo
runs Terraform locally with no CI/CD by design. Response-wrapping it by hand each time would
work but mostly just moves the manual-root-token problem somewhere else.

Went with the AWS auth method instead - the EC2 instance's own IAM role is the credential, so
there's no `secret_id` to invent a safe distribution story for at all. Wired up
`terraform/vault-config/auth.tf` (auth backend, client config, and a role bound to the Vault
node's own IAM role - no separate "app" instance exists in this sandbox, so it stood in as
the client). Looked the role up by name via a data source rather than hardcoding its ARN, so
the account ID never lands in a committed file, same rule as everywhere else here.

Couldn't test it from a laptop - IAM-type login has to be signed by the authenticating
identity itself, so proving it meant SSM'ing onto a Vault node and logging in from there.
Worked first try: token came back scoped to `inventory-service`, no human, no root token. Ran
the same read/write/unrelated-path proof as the original KV v2 policy test rather than trusting
that "login succeeded" was enough on its own - write and the unrelated path both came back 403.

## 2026-09-10 — Changelog redo: back to day headers, now nested with type

Revisited the changelog grouping from earlier today. Switching to pure type-grouping
(Features, Bug Fixes, Docs, ...) fixed the original complaint — no more hunting through every
day for "what changed on the Terraform side" — but it also threw away the one thing day
grouping was good for: knowing *when* something happened without leaving the file. Nested both:
day headers outer, type headers inner, newest-first throughout. Took a bit more Tera template
work than the flat version (`commit_groups` only groups whatever list you hand it, so each
day's commits have to be filtered out by hand first), but keeping both axes was worth the extra
template complexity.

## 2026-09-10 — Mounts and policies move from HCL blocks to a YAML list

Anticipated this directory growing past two resources, so followed up the initial import with
a generalization pass: one named `resource` block each doesn't scale to "add a mount
whenever," which is exactly the plan for this directory. Replaced the two blocks with
`vault_mount.this` and
`vault_policy.this`, both `for_each` over a new `vault-config.yaml`, so growing this out to
dynamic secrets or more app policies later is a YAML edit, not a Terraform edit.

Didn't touch the live resources to get there — `terraform state mv` onto the new `for_each`
addresses, then `terraform plan` came back clean on the first try. Same discipline as every
other change to this directory: the plan has to prove nothing moved before it's trusted.

## 2026-09-10 — Vault's own configuration joins the rest of the codebase

The KV mount and policy from earlier today existed only as CLI commands and shell history —
real, working, but invisible next to everything else in this repo, which is Terraform end to
end. Closed that gap: `terraform/vault-config/` now owns `vault_mount.secret` and
`vault_policy.field_guide_app` via the `hashicorp/vault` provider, with the policy document
itself as a separate `.hcl` file rather than an inline string.

Didn't recreate anything — imported the live resources and checked `terraform plan` before
trusting the config, which caught one real gap: the mount had never had a `description` set.
Applied that, then a second `plan` came back clean. Same rule as the AWS side: nothing
proceeds until Terraform's plan matches reality, not the other way around. Same credential
handling too — the Vault provider takes no config block, just reads `VAULT_ADDR` and friends
from the environment, supplied fresh through the SSM tunnel each session like everything
else in this build.

## 2026-09-10 — First real feature: static secrets, informed by a multi-tenancy comparison

Configuration work started for real. Enabled KV v2 at `secret/`, wrote a test secret,
confirmed versioning works. The part that actually mattered: wrote a least-privilege policy
and then *proved* it — created a token scoped to it and confirmed it could read its own
secret but got a clean 403 trying to write, and another 403 reaching an unrelated path.
Reading a policy back after writing it just confirms the HCL parsed; it says nothing about
whether the rules actually bite.

Before writing the policy, worked through the recommended pattern for multiple teams sharing
static secrets - a comparison of three approaches (path-namespaced single mount, separate
mounts per team, Enterprise Namespaces) grounded in concrete examples: a bank, and a
government agency. That was worth a permanent home rather than staying in conversation, so
it became `reference/patterns.md` - the first page in this guide that's explicitly conceptual
rather than "what we did," following the same rule established earlier: split guide content
from reference content once there's actually something guide-shaped and something
reference-shaped, not preemptively.

The multi-team discussion's real payoff: Namespaces aren't really about "does this team know
Vault" - they're about compliance and legal-entity boundaries (PCI scope, a subsidiary under
a different regulator) more than team skill level, and in practice organizations nest the
patterns rather than picking one - Namespaces for the big regulatory boundaries, path or mount
conventions for the finer structure inside each one.

Ran `vault operator init` for real. Tunneled to a Vault node via SSM port-forwarding straight
to its own 8200 — no bastion host, the access pattern this whole build was designed around
from the TLS decision onward. Needed one missing local dependency first: the `aws` CLI's
`ssm start-session` (interactive/port-forwarding) needs the separate `session-manager-plugin`
binary, which `ssm send-command` (used earlier for diagnostics) doesn't — installed it and
tried again.

Init succeeded first try: root token and 5 recovery key shares (threshold 3) generated,
piped straight into a new Secrets Manager secret, local copy shredded immediately. Never
printed a full value anywhere. `vault status` confirmed auto-unseal via KMS kicked in
instantly — sealed went straight to false, no manual step — and `vault operator raft
list-peers` showed all three nodes as voters, one leader, two followers.

Three-node HA Vault Enterprise, actually running, actually initialized, actually unsealed.
That was the goal on day one.

## 2026-09-10 — Changelog and journal: drawing a clean line

Asked directly - "is changelog the same as journal?" - which prompted a proper look at what
`CHANGELOG.md` had become: each entry was rendering the full commit body underneath a bold
summary, which is functionally what a journal entry does, just tied to one commit instead of a
work session. Stripped the body out of the changelog template entirely (back to one bold
summary line, nothing else) and made the journal the permanent narrative home - covers
commit-less work, written at story-beat grain instead of one entry per commit, which is what
keeps this page from just becoming the changelog with more words.

Also caught and fixed a structural bug introduced the same day: adding each commit's short
hash to its changelog line, using the same self-amending post-commit hook, doesn't converge -
a commit's hash changes every time it's amended, so "fix the hash" and "the hash is wrong
again" chase each other forever. Caught it running in the background, stopped it before it did
anything but churn the local reflog, and moved the whole hook to the `pre-commit` git stage
instead - at that point the commit being made doesn't exist yet, so `git-cliff` only ever sees
commits whose hashes are already permanent. One (structurally unavoidable) tradeoff: a
commit's own entry doesn't appear until the *next* commit runs the hook.

## 2026-09-10 — Homepage polish, and the cluster is genuinely healthy

Rewrote the homepage with Material grid cards and a real status checklist instead of a stale
"planning underway" line — needed three markdown extensions we didn't have yet (`attr_list`,
`md_in_html` for the card layout, `pymdownx.emoji` configured with Material's icon set for the
arrow icons), verified by actually rendering and screenshotting the page rather than trusting
a clean `mkdocs build`.

Also went back and confirmed, via SSM, that the fix below actually worked: all three nodes
`active`, running `2.1.0+ent`, `awskms` seal, HA via Raft, correctly `Initialized: false` /
`Sealed: true`. First real validation that this isn't just "Terraform said apply succeeded" —
Vault itself is up.

## 2026-09-10 — First real apply crash-looped: a license, not a Terraform, bug

`terraform/vault` applied cleanly — 19 resources, all green — and every node crash-looped
anyway. Terraform succeeding is not the same as Vault working. Dug in via SSM (`ec2_allow_ssm`
paid off immediately): `systemctl status vault` showed exit code 1, `journalctl -u vault`
had the real error — `license validation failed: invalid module: "platform-standard"`. Not
corrupted, not a Terraform bug: the module's default `vault_version` (`1.17.3+ent`) didn't
match what our license actually entitles.

Confirmed `2.1.0+ent` was a real, published release (`releases.hashicorp.com/vault/index.json`)
before pinning it — didn't want to guess a version string against a live account. Learned two
more things the hard way: updating a launch template doesn't touch already-running ASG
instances (needed a manual `aws autoscaling start-instance-refresh`), and the module's Route53
zone lookup defaults to public-zone semantics — fails against our private zone until
`route53_vault_hosted_zone_is_private = true` is set explicitly, even though the zone
obviously exists.

## 2026-09-10 — Dropped the real domain; no local AWS profile either

Had been planning to use a real personal domain, with a public DNS record pointing at an
internal load balancer and a security-group CIDR restriction for actual protection. Kept
stalling on a real dependency: that domain's Route53 zone lives in a *personal* AWS account,
separate from the HashiCorp sandbox, and needed re-authenticating into whichever profile hosts
it just to check. Reconsidered from first principles: Route53 **private** hosted zones don't
validate domain ownership at all — that only matters for public zones and publicly-trusted
CAs. Dropped the real domain entirely, generated a self-signed CA and
leaf cert declaratively via the `tls` Terraform provider (not a separate `openssl` script), and
created the private zone for `vault.sandbox.internal` — fully self-contained in the sandbox
account.

Separately, reconsidered how credentials get handled at all: had been writing a `hc-sandbox`
CLI profile to `~/.aws/credentials` for convenience. Even short-lived STS sessions sitting on
disk felt like more than necessary — deleted the profile, and every Terraform provider block
now takes credentials purely from environment variables, supplied fresh each session, never
persisted anywhere.

## 2026-09-10 — HVD module scaffolded, wired to prerequisites via remote state

`terraform/vault` calls `hashicorp/vault-enterprise-hvd/aws` directly, reading every input
(VPC/subnet IDs, KMS key ARN, secret ARNs, FQDN) from `terraform/prerequisites`'s state via
`data.terraform_remote_state` — no manual ARN copy-pasting between configs. Overrode a few
module defaults deliberately: 3 nodes instead of 6 (standard Raft HA quorum minimum, plenty
for a sandbox), `ec2_allow_ssm = true` so there's no need for a separate bastion host, and load
balancer ingress restricted to the VPC's own CIDR — access was always going to be via SSM
port-forwarding from inside the VPC, never real internet traffic.

## 2026-09-10 (crossing over from 2026-09-09) — Changelog automation

Manual `CHANGELOG.md` regeneration drifted 6 commits behind almost immediately — exactly the
risk flagged when that became a manual step. Fixed it properly rather than just catching up by
hand: a `post-commit` hook that self-amends the changelog into the very commit that triggered
it, safe from infinite recursion since re-triggering the hook on an unchanged commit message
produces identical output the second time around. Also iterated the actual format — grouped by
day instead of a permanent "[Unreleased]" label, ordered newest-first to match `git log`,
tightened into one-line-per-commit instead of a loose paragraph — before eventually removing
the commit body from the rendered output entirely, once the journal came back and having both
carry the same reasoning became pure duplication.

## 2026-09-09 — Prerequisites applied: VPC, KMS key, license

First real infrastructure in the sandbox account: a VPC (community
`terraform-aws-modules/vpc/aws` module — 3 public subnets just to host the NAT Gateway, 3
private subnets for the Vault nodes and the internal load balancer), a KMS key for
auto-unseal, and the Vault Enterprise license uploaded to Secrets Manager. 27 resources, state
in S3 with native locking (`use_lockfile`, GA since Terraform 1.11 — no DynamoDB table to
manage). While auditing the account for anything unexpected, found and deleted three unrelated
`lab-bucket-*` S3 buckets — leftover AWS training-lab artifacts, confirmed trivial (a 32-byte
`config.json` and 18-byte `document.txt` each) before touching them.

## 2026-09-09 — AWS survey: sandbox account, ap-southeast-2

Authenticated to the HashiCorp sandbox account (an internal credential broker issuing a
short-lived STS session) and settled on
`ap-southeast-2` as the working region, matching the existing personal AWS profiles. Along the
way: STS session credentials turned out to *not* be region-locked — a `describe-vpcs` call
succeeded in three different regions on the same session, disproving an initial (wrong)
assumption that the token was scoped to `us-west-2`.

Surveyed the sandbox account/region: only the AWS-managed default VPC (public subnets only,
no NAT gateways) and AWS-managed default KMS keys exist. All four prerequisites for the HVD
module — VPC, KMS key, license in Secrets Manager, TLS material in Secrets Manager — start
from scratch.

## 2026-09-09 — Chose the official HVD module over hand-rolled Terraform

Decided to deploy via HashiCorp's own [Validated Design module](https://github.com/hashicorp/terraform-aws-vault-enterprise-hvd)
(`hashicorp/vault-enterprise-hvd/aws`) rather than writing the ASG/LB/IAM setup from scratch.
Verified its actual prerequisites against the module's README rather than assuming: 3 private
subnets across distinct AZs, NAT gateways, a dedicated KMS key, and TLS/license material in
Secrets Manager.

## 2026-09-09 — Vault brand theme

Themed the site with Vault's real brand colors and logo, sourced directly from HashiCorp's
`design-system` GitHub repo rather than eyeballing a screenshot — brand gold is `#ffcf25`,
not the Material "amber" swatch used in the original scaffold. Black header/footer chrome
matches Vault's own "brand-alt" exception token (used because the gold fails contrast as UI
chrome). Official SVG glyph as the header logo, rendered to PNG for the favicon.

## 2026-09-09 — GitHub Pages deploy

Added a GitHub Actions workflow to build and deploy the site to GitHub Pages on every push to
`main`, using the native Pages Actions flow (no `gh-pages` branch to manage). Live at
<https://markcarriedo.github.io/vault-enterprise-field-guide/>.

## 2026-09-09 — Settling where the journal lives

Considered dropping the journal entirely in favor of treating `docs/guide/` +
`docs/reference/` as the sole published output, then a GitHub Wiki as a way to keep raw notes
fully outside the MkDocs build — ruled out because a wiki's git repo can't be initialized
without first creating a page through the GitHub web UI, which doesn't fit an automated
workflow. Kept it here, in `docs/journal/`, as part of the site.

(The question of where reasoning should live came up again once the changelog was built out
further — see the entries above for how that settled: a clean division where the changelog
stays mechanical and the journal carries the narrative.)

## 2026-09-09 — Public repo, secret scanning

Pushed the repo to GitHub as public (`markcarriedo/vault-enterprise-field-guide`, renamed from
the original `vault-enterprise-aws-ec2`). Added a [gitleaks](https://github.com/gitleaks/gitleaks)
pre-commit hook (via the [pre-commit](https://pre-commit.com) framework) to block accidental
credential commits before they land in git history — verified it actually catches a fake AWS
key before relying on it.

## 2026-09-09 — Field guide scaffolded

Set up this MkDocs site (Material theme) to document the Vault Enterprise on AWS EC2 build
as we go. No Vault work yet at this point — planning & prerequisites started the same day,
further down this page.
