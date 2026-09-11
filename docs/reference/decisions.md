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

## 2026-09-11 — Dynamic AWS secrets via assumed_role, not iam_user

**Context:** Static secrets (KV v2) prove Vault can store and control access to a value that
already exists; dynamic secrets are the actually-differentiated feature — Vault generates
the credential itself, on request, with its own lease. The AWS secrets engine offers two
main credential types: `iam_user` (create a real IAM user + access key per lease, delete on
revocation) and `assumed_role` (assume an existing role via STS, return the temporary
credentials, nothing created or deleted).

**Decision:** `assumed_role`. Added one narrowly-scoped IAM role (`vault-dynamic-demo`,
`sts:GetCallerIdentity` only — proving the mechanism, not granting real access) trusted by
the Vault nodes' own IAM role, plus an inline policy granting that existing role
`sts:AssumeRole` on the new one. `vault_aws_secret_backend` takes no explicit AWS
credentials, same fallback-to-instance-role pattern as the AWS auth method's client config.
Extended the existing `field-guide-app` policy (rather than writing a new one) with `read` on
`aws/creds/field-guide-app` — one app identity, policy scoped across two different secrets
engines.

**Alternatives considered:** `iam_user` — rejected as the default choice here specifically
because it requires granting Vault's own IAM role permission to create, tag, attach
policies to, and delete IAM users/access keys on the fly — a meaningfully broader and more
sensitive permission grant than `sts:AssumeRole` on one specific role ARN, for a sandbox
whose whole point is minimizing what any single identity can do.

**Consequences:** Verified with real AWS API calls, not just a successful `vault read` —
used the returned credentials against STS `get-caller-identity` and confirmed the resulting
identity was the assumed role, not Vault's own. Also verified (and documented as a gotcha)
that `assumed_role` lease revocation is soft: `vault lease revoke` stops Vault tracking the
lease but does not invalidate the underlying STS session, since AWS STS has no
general-purpose immediate-revocation API (confirmed against AWS's own IAM documentation,
which describes a session-start-time deny-policy workaround as the real mechanism — one
Vault doesn't apply automatically). Anyone reusing this pattern for real, sensitive AWS
access should size the TTL accordingly, since "revoked" doesn't mean "dead" for the
remaining TTL window.

---

## 2026-09-10 — AWS auth method instead of AppRole, to stop using the root token

**Context:** Everything so far — configuring mounts, policies, testing enforcement — used the
root token from `operator init`. Fine for early sandbox work, explicitly not fine to keep
doing (see the glossary's own note on root tokens). Needed a real auth method so something
other than a human could get a scoped token.

**Decision:** AWS auth method, not AppRole. An EC2 instance authenticates using its own IAM
role identity (a signed STS `GetCallerIdentity` request, `auth_type = "iam"`) — the
credential *is* the instance's already-existing role, nothing new to generate or distribute.
Added `vault_auth_backend`, `vault_aws_auth_backend_client`, and
`vault_aws_auth_backend_role` to `terraform/vault-config/auth.tf`, bound via
`bound_iam_principal_arns` to a Vault node's own IAM role (there's no separate "app" instance
in this sandbox, so it doubles as the client proving the pattern), `token_policies =
["field-guide-app"]`. The role is looked up with `data "aws_iam_role"` by **name**, not ARN —
the AWS account ID is structurally part of any IAM ARN, and this repo has never committed one;
resolving it dynamically at apply time keeps that true here too. `resolve_aws_unique_ids` set
to `false` deliberately — the default `true` would need `iam:GetRole`/`iam:GetUser`
permission added to the Vault node's own role just for this, not worth it for a direct,
stable ARN binding in a sandbox.

**Alternatives considered:** AppRole — Vault's more commonly-documented answer to "give an
app a token," and genuinely the right default in most environments. Rejected specifically
here: AppRole's `secret_id` needs a trusted distributor to hand it out safely (CI/CD
injecting it, an orchestrator response-wrapping it), and this repo deliberately runs
Terraform locally only, with no pipeline (see the "local-only Terraform" decision). Without
that automation, "safely vending a secret_id" reduces to a human doing it by hand, which
defeats the reason to automate auth in the first place. AWS auth doesn't have this problem:
there's no secret to vend, since the instance's IAM role already *is* the credential.

**Consequences:** Verified end-to-end, not just applied — IAM-type login has to be tested
from the authenticating instance itself, since the request must be signed by the caller's own
credentials; a laptop with different AWS credentials can only prove the wrong identity is
rejected, not that the right one works. SSM'd onto a Vault node, ran `vault login
-method=aws role=field-guide-app`, got a token with `field-guide-app` attached, then repeated
the same enforcement proof as the KV v2 policy (read succeeds, write and an unrelated path
both 403). This pattern only works for clients that are themselves EC2 instances with a real
IAM identity; a genuinely external or non-AWS client would still need AppRole (or another
method) and would have to solve the `secret_id`-vending problem for real.

---

## 2026-09-10 — Changelog nested: day headers, then commit type within each day

**Context:** Grouping purely by commit type (see below) traded away something worth keeping —
with no date information left anywhere in `CHANGELOG.md`, there was no way to tell at a glance
what happened on a given day without cross-referencing the journal or `git log`.

**Decision:** Nest both axes: `## YYYY-MM-DD` day headers (newest first), each containing
`### <type>` subheadings (🚀 Features, 🐛 Bug Fixes, etc.) with that day's commits of that
type, newest-first within the group. Implemented by filtering `commits` down to one day's
commits (`concat`-building a list across a manual loop, since `commit_groups` needs a
pre-filtered list to group), then running the existing `commit_groups(groups=
commit_parsers_groups)` on that subset per day.

**Alternatives considered:** Type-only grouping (the immediately preceding version of this
file) - reconsidered same-day once it became clear losing dates entirely made the file harder
to scan, not easier. A strict single reverse-chronological list with a type label per line -
still rejected for the same reason as before: loses at-a-glance scannability by type.

**Consequences:** Slightly more complex Tera template (a manual per-day filter step, since
`commit_groups` only groups a list you hand it, not the whole commit history at once) — worth
it for keeping both axes. Within a day, groups still order by the fixed `commit_parsers`
sequence, not recency, same tradeoff as the type-only version.

## 2026-09-10 — Changelog grouped by commit type instead of by day (superseded, see above)

**Context:** `CHANGELOG.md` grouped entries under a `## YYYY-MM-DD` heading per day, newest
day first. Scanning for "what's changed on the Terraform side" or "what docs changed" meant
reading every day's entries and filtering by eye — the day grouping tells you *when*, not
*what kind*.

**Decision:** Switched `cliff.toml`'s template to `git-cliff`'s built-in
`commit_groups(groups=commit_parsers_groups)`, grouping by Conventional Commits type (🚀
Features, 🐛 Bug Fixes, 📚 Documentation, etc. — the emoji/label groups were already defined
in `commit_parsers`, just unused since this repo doesn't tag releases). `sort_commits =
"newest"` keeps each group newest-first, same as before.

**Alternatives considered:** A strict single reverse-chronological list with a type label per
line (no headers) - rejected, loses the at-a-glance scannability that's the whole point of
this change.

**Consequences:** Revisited the same day — see the entry above, which nests day headers back
in above the type headers rather than dropping dates entirely.

## 2026-09-10 — Mounts and policies driven from YAML instead of one resource block each

**Context:** `terraform/vault-config/main.tf` declared `vault_mount.secret` and
`vault_policy.field_guide_app` as named resource blocks. That's fine for two resources, but
the plan for this directory is to grow — dynamic secrets, PKI, more app policies — and a new
named block per mount or policy means touching `.tf` (and knowing HCL) for what's really just
new data, not new logic.

**Decision:** Introduced `vault-config.yaml` as the single source of truth for mounts and
policies, and rewrote `main.tf` to `for_each` over it with `yamldecode()` — one
`vault_mount.this` and one `vault_policy.this`, keyed by mount path / policy name. Policy
bodies stay as separate `.hcl` files (referenced from YAML by filename), not inlined into the
YAML, so they keep reading and diffing like the Vault policy documents they are. Migrated the
existing state with `terraform state mv` rather than destroy/recreate, and confirmed
`terraform plan` showed zero changes before trusting it.

**Alternatives considered:** A `.tfvars` file with the same shape - rejected, YAML is more
approachable for this project's actual editing pattern (adding one mount at a time by hand)
and doesn't require any Terraform-specific syntax knowledge. Terraform modules per resource
type - rejected as overkill for two resource types and a handful of instances; revisit if
this directory's resource *types* (not instances) actually grow.

**Consequences:** Adding a mount or policy is now a YAML edit plus (for a policy) a new
`.hcl` file - no `.tf` changes, no new resource address to think about. The tradeoff: `for_each`
loses the descriptive resource names Terraform CLI output used to have
(`vault_mount.this["secret"]` instead of `vault_mount.secret`) - deliberate, since the map key
already carries that meaning.

## 2026-09-10 — Vault's own config moved into Terraform, not just AWS infrastructure

**Context:** The KV v2 mount and `field-guide-app` policy were created with plain `vault`
CLI commands, same session as the AWS work but tracked nowhere - the only record was shell
history and the journal. Every other piece of this build (VPC, KMS, the cluster itself) is
Terraform-managed and reviewable in a diff; Vault's internal config wasn't, purely because it
happened first and moving fast mattered more at the time.

**Decision:** Created `terraform/vault-config/`, using the `hashicorp/vault` provider, to
manage `vault_mount.secret` and `vault_policy.field_guide_app`. Rather than destroying and
recreating them, ran `terraform import` against the live resources and confirmed
`terraform plan` showed zero drift before treating the config as authoritative - proof the
`.tf` files describe reality exactly, not an approximation of it. The policy itself lives in
a separate `.hcl` file (`policies/field-guide-app.hcl`), loaded via `file()`, so it reads and
diffs like the policy document it is rather than an escaped inline string.

**Alternatives considered:** Leaving Vault config as tracked-but-manual CLI steps documented
in the guide - rejected, since "documented" and "enforced" aren't the same thing, and drift
between the doc and the live cluster would only be caught by manually re-checking. Recreating
the resources from scratch under Terraform instead of importing - rejected, since that would
mean an unnecessary destroy/recreate of a working mount and policy purely for tooling
convenience.

**Consequences:** Same credential pattern as everywhere else in this repo - the `vault`
provider takes no config block, reading `VAULT_ADDR`/`VAULT_TOKEN`/`VAULT_CACERT`/
`VAULT_TLS_SERVER_NAME` from the environment, supplied fresh per session, nothing persisted.
Any future secrets engine, policy, or auth method should go here rather than being run
ad hoc against the cluster.

## 2026-09-10 — Cluster initialized; root token and recovery keys never touched disk or chat

**Context:** `vault operator init` produces a root token and (with KMS auto-unseal) recovery
key shares — genuinely sensitive, one-time output. Needed a real plan for handling it before
running the command, not an afterthought.

**Decision:** Tunneled to a Vault node via SSM port-forwarding (`AWS-StartPortForwardingSession`
directly to the node's own 8200, no bastion — the access pattern this was built for from the
start). Ran `vault operator init -format=json` straight into a file in the session scratchpad
(never the repo), immediately piped its contents into a new AWS Secrets Manager secret
(`vault-enterprise/init-output`), then shredded the local file. Only a redacted confirmation
(root token's first 8 characters, recovery share count) was ever displayed - never the full
values.

**Alternatives considered:** Displaying the output directly for the user to save manually -
rejected; the output would land in this conversation's transcript and shell history, and a
public-repo project is exactly the wrong place to get casual about that, even though the
transcript itself isn't the repo. Storing it via Terraform - rejected, `operator init` is a
one-time imperative operation, not infrastructure with a lifecycle Terraform should own.

**Consequences:** Retrieving the root token now requires reading
`vault-enterprise/init-output` from Secrets Manager directly (`aws secretsmanager
get-secret-value`) - there's no copy anywhere else, by design. Local prerequisite discovered
along the way: SSM port-forwarding needs the `session-manager-plugin` binary installed
separately from the `aws` CLI itself (`brew install --cask session-manager-plugin`) - the
plain CLI's own `ssm send-command` (used earlier for diagnostics) doesn't need it, but
interactive/port-forwarding sessions do.

---

## 2026-09-10 — Changelog hashes: pre-commit stage instead of post-commit self-amend

**Context:** Wanted each changelog entry to show its commit's short hash for direct
traceability (`git blame` works today but isn't as immediate as just reading the hash off the
line). First attempt embedded `commit.id` in the existing post-commit self-amend hook and hit
an unrecoverable infinite loop: a commit's hash changes every time it's amended, so "fix the
hash" and "the hash is now wrong again" chase each other forever. Caught it running in the
background, stopped it, reverted before anything was pushed.

**Decision:** Move the regeneration hook to the `pre-commit` **stage** (not just "the
pre-commit framework" - the actual git hook stage that runs before the commit object exists)
and drop the amend logic entirely. At that point `git-cliff` can only ever see already-existing
commits, whose hashes are permanently fixed - safe to render by construction, not by careful
avoidance. The hook now just regenerates and `git add`s the file; git creates the commit from
whatever's staged once hooks finish, so the update lands in the same commit without any amend.

**Alternatives considered:** Keep post-commit, omit the hash only for the commit currently
being amended - technically workable but adds real template complexity (detecting "is this
the newest entry") for a smaller win than just switching stages. A separate trailing "chore:
update changelog" commit each time - rejected originally for the same reason it's still
rejected: needless commit noise.

**Consequences:** A commit's own changelog entry (and hash) doesn't appear until the *next*
commit runs the hook - its hash simply doesn't exist yet during its own pre-commit phase.
Verified end-to-end: committed the config change itself, confirmed its own entry was correctly
absent, then this entry to confirm the previous commit picks up its hash on the very next one.
Reordered gitleaks to run after this hook in `.pre-commit-config.yaml`, so it also scans the
freshly regenerated `CHANGELOG.md` before any commit is allowed to complete.

---

## 2026-09-10 — Journal restored; changelog made purely mechanical

**Context:** Retiring the journal in favor of a git-cliff changelog (see below) relied on
commit bodies carrying the reasoning that used to live in journal prose. In practice this
created real overlap: `CHANGELOG.md` entries were rendering the full commit body underneath a
bold summary, which is functionally the same content a journal entry would carry, just
attached to a single commit instead of synthesized across a work session. Asked directly
("is changelog the same as journal?") the honest answer was no - the changelog is
commit-scoped and terser, and has no home for work that never touched a file - but the actual
rendered output had drifted close enough to count as duplication anyway.

**Decision:** Bring the journal back (`docs/journal/`, in the site nav) as the narrative home -
free-form, covers commit-less work, written at the grain of a story rather than one entry per
commit. Strip `commit.body` out of the `cliff.toml` template entirely, so `CHANGELOG.md` goes
back to being purely mechanical: one bold `type(scope): summary` line per commit, nothing else.

**Alternatives considered:** Keeping the body in the changelog and dropping the journal
(already tried - see "Retire the journal" below - concluded it wasn't sufficient). Keeping
both with bodies in the changelog too - rejected as the exact duplication this decision exists
to fix.

**Consequences:** Journal entries need writing by hand again, at a coarser grain than
individual commits (grouping related commits into single narrative beats, not paraphrasing
each one) - otherwise the journal just becomes the changelog with more words, recreating the
same overlap in prose form. Commit bodies are still good practice for `git log`/`git blame`
context even though they no longer surface in `CHANGELOG.md`.

---

## 2026-09-10 — Pin vault_version to 2.1.0+ent, not the module's 1.17.3+ent default

**Context:** First `terraform apply` of `terraform/vault` succeeded (19 resources), but all
three nodes crash-looped: `Error initializing core: licensing could not be initialized:
license validation failed: 1 error occurred: * invalid module: "platform-standard"`. Not an
infrastructure bug — cloud-init and the install script completed cleanly; `systemctl status
vault` showed the Vault process itself refusing to start over a license entitlement mismatch
against the module's default version (`1.17.3+ent`).

**Decision:** Set `vault_version = "2.1.0+ent"` explicitly (module input, overriding its
default). Confirmed `2.1.0+ent` is a real published release via
`releases.hashicorp.com/vault/index.json` before pinning it, rather than guessing a version
string. Applied via `terraform apply` (updates the launch template's rendered user-data) plus
an ASG instance refresh (`aws autoscaling start-instance-refresh`) — a template change alone
doesn't touch already-running instances.

**Alternatives considered:** None seriously - once the error pointed at a specific version's
license/module check, pinning to a version known to match the license was the direct fix.
Didn't attempt to decode or debug the license file's own contents beyond confirming it's
neither JWT nor plain base64 (an opaque HashiCorp-proprietary format) - not something worth
reverse-engineering when the fix was already known.

**Consequences:** `terraform/vault/main.tf` now pins an explicit Vault version instead of
trusting the module default - worth revisiting if the module's default is later bumped past
whatever this license actually entitles.

---

## 2026-09-10 — TLS: private Route53 zone + self-signed CA instead of a real domain

**Context:** Originally planned to use a real personal domain the user owns, with a public
DNS record pointing at an internal-facing load balancer and a security-group CIDR restriction
for actual protection. That kept stalling on a real dependency: that domain's Route53 zone
lives in a *personal* AWS account, separate from the HashiCorp sandbox, and needed
re-authenticating into whichever profile hosts it just to check.

**Decision:** Drop the real-domain requirement entirely. Use `vault.sandbox.internal`,
resolved by a **Route53 private hosted zone** associated with our VPC — private zones don't
validate domain ownership at all (that only matters for public zones, and for publicly-trusted
CAs like Let's Encrypt/ACM validating a cert). Cert is a self-signed CA + leaf, generated
declaratively via the `hashicorp/tls` Terraform provider (not a separate `openssl` script) so
it lives in state alongside everything else.

**Alternatives considered:** Self-signed cert with no DNS at all, just a local `/etc/hosts`
entry pointing the name at `127.0.0.1` (since access is via SSM port-forwarding to
`localhost` anyway) — rejected as further from real practice: no real enterprise Vault
deployment relies on per-laptop `/etc/hosts` edits, whereas centralized internal DNS
(private zone, or on-prem DNS with conditional forwarding) is standard. A real enterprise CA
(ACM Private CA) instead of a self-signed one — rejected on cost (~$400/month) for a sandbox
with no other use for it; the *architecture* (private zone + PKI-issued cert + trust
distribution) still matches enterprise practice, only the specific CA choice is a sandbox
stand-in.

**Consequences:** Fully self-contained in the sandbox account now — no dependency on the
user's personal AWS accounts at all for this build. Anyone actually connecting to Vault needs
the self-signed CA cert trusted locally (or `-tls-skip-verify` for casual testing), since it's
not a publicly-trusted CA.

---

## 2026-09-09 — Auto-regenerate CHANGELOG.md via a post-commit hook

**Context:** Moving `CHANGELOG.md` to a committed, root-level file (see "move CHANGELOG.md to
the repo root" below) made it a manual regeneration step — and it immediately drifted 6
commits behind, exactly the risk that decision flagged. Manual discipline wasn't enough.

**Decision:** A `post-commit` hook (`scripts/update-changelog.sh`), installed via the existing
`pre-commit` framework alongside gitleaks, regenerates `CHANGELOG.md` after every commit and
amends the result into that same commit if it changed — no separate "update changelog"
commits cluttering history. Safe from infinite recursion: the amend re-triggers the hook, but
git-cliff's output depends only on commit messages (unchanged by `--no-edit`), so the second
pass produces identical content, sees no diff, and exits.

**Alternatives considered:** A `pre-commit`-stage hook — rejected, it runs before the commit
object exists, so git-cliff can't see the commit it's meant to summarize. CI-side generation —
rejected earlier already (see below) since the site doesn't depend on this file.

**Consequences:** `pre-commit install` now sets up both `pre-commit` and `post-commit` hook
types (`default_install_hook_types` in `.pre-commit-config.yaml`) — one install command still
covers everything. Requires `git-cliff` installed locally; the hook skips gracefully (doesn't
block the commit) if it isn't. Every local commit now amends immediately after creation, so
`git log` timestamps/hashes for the amended commit reflect the amend time, not the original
`git commit` invocation — inconsequential for a solo workflow.

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
journal entirely. `CHANGELOG.md` lives at the repo root as a normal, committed file — a repo
artifact, not part of the published MkDocs site or its nav (an earlier version of this
decision embedded it into the site via a snippet-include; reverted — root-only is simpler and
matches where people actually expect a changelog).

**Alternatives considered:** Keeping both (journal for reasoning, git-cliff for a terse
commit list) — rejected as redundant once reasoning lives in commit bodies instead.
Rewriting existing commit history to retrofit Conventional Commits — rejected; this repo is
public and already pushed, so rewriting published history isn't worth it. Existing commits
are kept as-is and fall into an "Other" bucket in the changelog (`filter_unconventional =
false` in `cliff.toml`) rather than being dropped or rewritten.

**Consequences:** Every future commit needs a `type(scope): summary` line and, where the
change isn't self-explanatory, a body paragraph explaining why. `CHANGELOG.md` is generated
(via `git-cliff`) but committed like any other file — it must be regenerated and committed by
hand alongside each change (`git-cliff -o CHANGELOG.md`); nothing currently checks it's
up to date, so it can drift if that step is forgotten. CI no longer touches it, since the
site doesn't depend on it. Work that produces no commit at all (pure investigation, a
decision reached through discussion) still has no home unless it's folded into the next
related commit's body.

---

## 2026-09-09 — No local AWS profile; credentials via environment variables only

**Context:** Had created a local `hc-sandbox` CLI profile (in `~/.aws/credentials`) to hold
the sandbox credentials (issued by an internal credential broker), so Terraform/AWS CLI
commands didn't need the raw values re-supplied each time. Reconsidered — even though the
credentials are short-lived STS sessions, persisting them to a profile file means they sit on
disk (readable by anything with local file access) for the life of that session, however
short.

**Decision:** No local AWS profile for the sandbox account, and no `profile` argument in any
Terraform provider block. Credentials are supplied purely via the standard AWS SDK environment
variables (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`) for the duration
of a single command/session, never written to `~/.aws/credentials`.

**Consequences:** Every Terraform/AWS CLI invocation needs those three env vars exported first
— there's no persistent local profile to fall back on. This supersedes the `hc-sandbox` profile
mentioned in the "Sandbox account and region" decision below; the account/region choice there
still stands, only the credential-storage mechanism changed.

---

## 2026-09-09 — Sandbox account and region: HashiCorp sandbox, ap-southeast-2

**Context:** Needed a target AWS account/region to build in. Personal AWS profiles were an
option, but a HashiCorp sandbox account (issued via an internal credential broker) is more
appropriate — isolated from
personal infra, and expected to be disposable.

**Decision:** Build in the HashiCorp sandbox account, region `ap-southeast-2`. Chosen for
consistency with existing personal profiles (both `ap-southeast-2`) and latency. (Credential
storage mechanism superseded — see the "No local AWS profile" decision above.)

Note: STS session credentials are *not* region-locked — verified by successfully calling
`describe-vpcs` in three different regions with the same session. An initial region guess had
come from a hint embedded in the STS token's structure, not an actual restriction — worth
remembering next time a token needs a region assumption.

**Consequences:** All Terraform/AWS CLI work targets this account, region `ap-southeast-2`;
credentials are short-lived (internal credential broker/STS) and will need periodic refresh.
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
