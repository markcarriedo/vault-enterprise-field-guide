# Journal

Dated field notes from the build, in the order things happened. Newest entries at the top.
For the "why" behind a specific choice, see the [decision log](../reference/decisions.md); for
the mechanical commit-by-commit record, see [`CHANGELOG.md`](https://github.com/markcarriedo/vault-enterprise-field-guide/blob/main/CHANGELOG.md)
at the repo root. This page sits between the two: the story, at a coarser grain than either.

---

## 2026-09-10 — First real feature: static secrets, and a detour into multi-tenancy

Configuration work started for real. Enabled KV v2 at `secret/`, wrote a test secret,
confirmed versioning works. The part that actually mattered: wrote a least-privilege policy
and then *proved* it — created a token scoped to it and confirmed it could read its own
secret but got a clean 403 trying to write, and another 403 reaching an unrelated path.
Reading a policy back after writing it just confirms the HCL parsed; it says nothing about
whether the rules actually bite.

Went on a real tangent mid-task: asked about the recommended pattern for multiple teams
sharing static secrets, which turned into a proper comparison of three approaches
(path-namespaced single mount, separate mounts per team, Enterprise Namespaces) grounded in
concrete examples - a bank, the ATO. Worth writing up somewhere more permanent than a chat
transcript, so it became `reference/patterns.md` - the first page in this guide that's
explicitly conceptual rather than "what we did," following through on a rule I'd suggested a
few turns earlier: split guide content from reference content, but only once there's actually
something guide-shaped and something reference-shaped, not preemptively.

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

## 2026-09-10 — Journal, again: changelog had drifted into overlap

Asked directly - "is changelog the same as journal?" - and the honest answer forced a real
look at what `CHANGELOG.md` had become: each entry was rendering the full commit body
underneath a bold summary, which is functionally what a journal entry does, just tied to one
commit instead of a work session. Stripped the body out of the changelog template entirely
(back to one bold summary line, nothing else) and brought the journal back for good - covers
commit-less work, written at story-beat grain instead of one entry per commit, which is what
keeps this page from just becoming the changelog with more words.

Also chased down a self-inflicted bug the same day: tried adding each commit's short hash to
its changelog line, using the same self-amending post-commit hook. A commit's hash changes
every time it's amended - "fix the hash" and "the hash is wrong again" chase each other
forever. Caught it running in the background, stopped it before it did anything but churn the
local reflog, and moved the whole hook to the `pre-commit` git stage instead - at that point
the commit being made doesn't exist yet, so `git-cliff` only ever sees commits whose hashes
are already permanent. One (fully unavoidable) tradeoff: a commit's own entry doesn't appear
until the *next* commit runs the hook.

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

## 2026-09-10 (crossing over from 2026-09-09) — Changelog automation, twice

First automated `CHANGELOG.md` regeneration with a `post-commit` hook — then immediately
proved why that mattered: it wasn't wired up for one stretch of commits and drifted 6 behind
almost right away. Fixed by making the hook self-amend the changelog into the very commit that
triggered it (safe from infinite recursion, since re-triggering the hook on an unchanged
message produces identical output the second time). Also spent a while iterating the actual
format — grouped by day instead of a permanent "[Unreleased]" label, ordered newest-first to
match `git log`, tightened into one-line-per-commit instead of a loose paragraph — before
eventually removing the commit body from the rendered output entirely, once the journal came
back and having both carry the same reasoning became pure duplication.

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

Authenticated to the HashiCorp sandbox account (Doormat-issued STS session) and settled on
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

## 2026-09-09 — Journal dropped, then revived (the first time)

Briefly dropped this journal entirely in favor of treating `docs/guide/` + `docs/reference/`
as the sole published output. Reconsidered — a chronological log alongside the guide is worth
keeping. Considered a GitHub Wiki for it (keeps it fully out of the MkDocs build) but the
wiki's git repo can't be initialized without first creating a page through the GitHub web UI,
which doesn't fit an automated workflow — reverted to keeping the journal here.

(It got dropped a *second* time not long after this, in favor of a git-cliff changelog with
reasoning folded into commit bodies — and came back again once that started overlapping with
the changelog rather than replacing it. Third time's the charm, hopefully.)

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
