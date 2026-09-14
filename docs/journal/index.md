# Journal

Dated field notes from the build, in the order things happened. Newest entries at the top.
For the "why" behind a specific choice, see the [decision log](../reference/decisions.md); for
the mechanical commit-by-commit record, see [`CHANGELOG.md`](https://github.com/markcarriedo/vault-enterprise-field-guide/blob/main/CHANGELOG.md)
at the repo root. This page sits between the two: the story, at a coarser grain than either.

---

## 2026-09-14 — Transit, and the security model actually held up under test

Picked Transit off the roadmap - encryption as a service, the real point being that an app can
use a key without ever seeing it. Mount and key went in through the same generic YAML pattern
everything else already uses, so the interesting part was the policy: `update` on encrypt and
decrypt only, nothing on the key's own metadata or export paths. See the
[decision log](../reference/decisions.md) for the full reasoning.

Didn't just trust the policy file - logged in as the actual app identity and tried to read and
export the key directly. Both came back a clean 403, while encrypt/decrypt round-tripped real
data perfectly. Picked up a genuine, reproducible Enterprise HA quirk along the way: the very
first request after a fresh login occasionally 412s going through the load balancer, since the
login write and the next read can land on different Raft nodes before they've caught up with
each other. Resolved on retry every time - documented as a real characteristic of this access
path, not something to paper over. Rotated the key afterward and confirmed old ciphertext still
decrypts under its original version while new writes move to the new one automatically, which
is really the whole point of a versioned key.

## 2026-09-14 — Turned on cleanup_dead_servers, then found out it doesn't mean what it sounds like

Asked directly after the node-replacement test: should `cleanup_dead_servers` actually be
turned on, since we'd just done its job by hand? Found the `hashicorp/vault` provider already
has a resource for it - added `terraform/vault-config/autopilot.tf`, clean single-resource
apply, no drift elsewhere.

Then didn't just assume it fixed the gap - repeated the exact same termination test to check.
It didn't clean up automatically, and the reason turned out to matter: removal is gated on
`dead_server_last_contact_threshold` (24h by default), not on `cleanup_dead_servers` alone,
and HashiCorp's own docs recommend keeping that threshold high on purpose, to avoid pruning a
node that's only briefly unreachable. So the change is real and worth keeping as a long-horizon
safety net, but the manual `remove-peer` step in the runbook stays exactly as written. Worth
remembering: a config flag named after the behavior you want doesn't always mean the behavior
happens on the timescale you assumed.

## 2026-09-14 — Killed a node on purpose, and the ASG's health check lied about it

Picked node replacement off the roadmap - a Raft cluster's real resilience story includes
surviving a node loss, not just a snapshot restore. Checked Autopilot's actual config on this
cluster first rather than assuming: `cleanup_dead_servers` is off by default and the HVD module
doesn't turn it on, so terminating a node was always going to need a manual peer cleanup step.
Confirmed with a real termination of a healthy follower. See the
[decision log](../reference/decisions.md) for the full before/after detail.

The genuinely unplanned part: the first replacement instance's boot silently failed a `dpkg`
lock race against `unattended-upgrades`, so Vault never actually installed - and the ASG kept
reporting it "Healthy" the entire time, since its health check only looks at EC2 status, never
at Vault itself. Only `vault operator raft list-peers` told the truth. Terminated the broken
instance, let the ASG try again, and the second attempt joined cleanly and got auto-promoted to
voter in about 15 seconds. Two real findings from one test - the kind of thing no amount of
reading Autopilot's docs would have surfaced on its own.

## 2026-09-13 — Runbooks gets its own place in the nav

Flagged by a simple observation: the operations page had quietly grown into the biggest file
in the Guide, and it never really belonged in a numbered "do this once" sequence to begin with.
Split it out to `docs/runbooks/index.md` as its own top-level nav section - see the
[decision log](../reference/decisions.md) for the reasoning and what got renumbered.

Also raised, in the same breath, whether the journal should fold back into the changelog -
the last couple of entries here had drifted into restating the decision log almost word for
word. Decided to leave the journal as-is rather than redo a move already tried and reverted
once, and went back afterward to actually trim the duplicative entries and fold four older
ones about the changelog/journal's own tooling into a single note - the fix flagged here,
followed through rather than just written down.

Followed up the same day: one page for five runbooks was already showing its age, so split
each into its own page under `docs/runbooks/`, `index.md` now just a landing page linking out.
Deep links from elsewhere in the guide (Configuration's Raft snapshot mention, for one) now
land on an actual page start instead of scrolling to an anchor mid-page.

## 2026-09-13 — Regenerating the root token, and a real Vault 2.0 surprise along the way

Picked root token regeneration off the certification roadmap - the one credential in this
build with no TTL, worth a tested runbook rather than an assumption. First attempt didn't work
at all: `vault operator generate-root -init` came back `403 permission denied` with no token
set, contradicting older Vault docs describing this endpoint as needing only recovery key
fragments. Pulled the actual audit log entry for the request (a nice payoff from yesterday's
CloudWatch work), then checked HashiCorp's current docs directly rather than trusting cached
knowledge of the command: Vault 2.0 made `sys/generate-root` require an authenticated token by
default, closing a real gap where an attacker could submit bogus key fragments to block
legitimate use. See the [decision log](../reference/decisions.md) for the full reasoning and
the verified procedure.

Also needed two separate approvals mid-session for reading and then using the actual root
token/recovery key secret - reasonable guardrails for the most sensitive credential in the
whole build, no different in spirit from the care taken with the original `operator init`
output.

## 2026-09-12 — Raft snapshots, tested the only way that actually proves anything

Closed the last big certification-topic gap: disaster recovery for Integrated Storage. Built a
durable S3 landing spot first, reusing the Terraform state bucket's security pattern, and
skipped Vault Enterprise's own automated snapshot agent for now - see the
[decision log](../reference/decisions.md) for why.

The part that mattered was the test, not the mechanism. "Simple on paper" (`save`, `restore`)
isn't the same as verified, and a restore is genuinely cluster-wide - so wrote a disposable
marker key *after* taking the snapshot, restored it, then checked both directions: the marker
gone (proof the restore actually reloaded state, not a no-op) and real data untouched, with
cluster topology identical before and after. A disposable, timestamped marker turns out to be
the reusable trick here - it's the only way to tell "the restore did nothing" from "the restore
worked," which re-checking already-known-good data can't distinguish. Everything came back
clean on the first attempt.

## 2026-09-12 — Audit logs land in CloudWatch, after one genuine ordering bug

Closed the cheapest, highest-value gap left on the certification-topic sweep: audit logging,
zero coverage until now. First instinct - bolt the CloudWatch Agent onto the HVD module's own
bootstrap via `custom_startup_script_template` - turned out wrong once actually checked: that
variable replaces the module's entire install script rather than extending it, not worth the
risk to a running cluster. Used SSM State Manager instead - see the
[decision log](../reference/decisions.md) for the full reasoning.

The real find was operational, not architectural: `terraform apply` reported success, but
`describe-association-executions` showed the configure step had actually failed a few seconds
after install reported success on the exact same instances - `depends_on` had ordered their
*creation* in Terraform, not their *execution* on the instance. Fixed it by hand, then added a
recurring schedule so a future instance losing the same race heals itself. Closed the loop by
reading real CloudWatch events back and confirming sensitive fields come through hashed, not
by trusting "the association shows Success" alone.

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

## 2026-09-10 — Changelog and journal, sorted into their final shape

Automated `CHANGELOG.md` regeneration via a self-amending post-commit hook, then spent the rest
of the day iterating on what it should actually contain: grouped by commit type first (fixed
"where's the Terraform stuff" but lost at-a-glance dates), then nested day headers with type
groups inside them to get both. Caught one real bug along the way - adding a commit's own short
hash via that same self-amending hook doesn't converge, since amending changes the hash - fixed
by moving the whole thing to the `pre-commit` git stage, where the commit being made doesn't
exist yet, so git-cliff only ever sees permanent hashes.

The bigger question underneath it: where should reasoning actually live? Ruled out a GitHub
Wiki for raw notes early on (its repo can't be initialized without first creating a page
through the web UI - doesn't fit an automated workflow), then drew a clean line once the
changelog started rendering full commit bodies and duplicating what the journal was already
for: `CHANGELOG.md` stays purely mechanical, one bold line per commit; this journal carries the
narrative; the [decision log](../reference/decisions.md) carries anything ADR-worthy. That
division has held since.

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
