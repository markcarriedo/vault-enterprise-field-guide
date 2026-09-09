## [Unreleased]

### 🐛 Bug Fixes

- *(ci)* Stop passing --config twice to git-cliff-action

The action already builds --config=<config> from its own config input
and appends args verbatim, so args also containing --config duplicated
the flag and made git-cliff refuse to run. Verified the composed
command locally before pushing this time.


### 📚 Documentation

- Replace journal with a git-cliff generated changelog

Journal was hand-written narrative; decided reasoning can live in commit
bodies instead, rendered into the changelog by a custom cliff.toml
template (renders commit.body, not just the one-line summary). Adopting
Conventional Commits from here on so git-cliff can group entries by type
instead of dumping everything under "Other". Existing history is kept
as-is in that "Other" bucket (filter_unconventional = false) rather than
rewritten, since this repo is already public.

CHANGELOG.md is generated (git-cliff), gitignored, and rebuilt in CI
before every Pages deploy; docs/changelog.md pulls it in via a
pymdownx.snippets include.


### 💼 Other

- Scaffold MkDocs field guide for Vault Enterprise on AWS EC2

Material theme, journal/guide/reference structure, mermaid support.

Claude-Session: https://claude.ai/code/session_01W8wX9ho5zsL4nSkjw8ZJSM

- Add gitleaks pre-commit hook to block accidental secret commits

Claude-Session: https://claude.ai/code/session_01W8wX9ho5zsL4nSkjw8ZJSM

- Lead README with the Vault content, push MkDocs mechanics below

Claude-Session: https://claude.ai/code/session_01W8wX9ho5zsL4nSkjw8ZJSM

- Drop the journal — guide + reference are the published output

Journaling stays a working process, not a published artifact.

Claude-Session: https://claude.ai/code/session_01W8wX9ho5zsL4nSkjw8ZJSM

- Deploy docs to GitHub Pages via Actions, wire up the Pages URL

Claude-Session: https://claude.ai/code/session_01W8wX9ho5zsL4nSkjw8ZJSM

- Theme the site with Vault's official brand colors and logo

Colors and icon sourced from hashicorp/design-system (vault-brand #ffcf25,
vault-500 #9a6f00 for accessible light-mode links, vault-200 #ffe543 for
dark-mode links). Black header/footer chrome matches the "brand-alt" token
HashiCorp itself uses where the gold doesn't work as chrome.

Claude-Session: https://claude.ai/code/session_01W8wX9ho5zsL4nSkjw8ZJSM

- Document prerequisites for the HVD Vault Enterprise module

Planning page now tracks the four prerequisites (VPC, KMS key, license +
TLS material in Secrets Manager); decision log records why we're using
HashiCorp's official HVD module instead of hand-rolled Terraform.

Claude-Session: https://claude.ai/code/session_01W8wX9ho5zsL4nSkjw8ZJSM

- Record target environment and AWS survey findings

HashiCorp sandbox account, ap-southeast-2. No account IDs/ARNs recorded
since this repo is public. Survey confirms all four prerequisites need
to be built from scratch (default VPC only, no usable KMS keys).

Claude-Session: https://claude.ai/code/session_01W8wX9ho5zsL4nSkjw8ZJSM

- Revive the journal, backfilled with the day's work

Wiki was a dead end (its git repo can't be initialized without first
creating a page through the web UI) so the journal lives back in
docs/journal/, in the MkDocs nav as originally intended.

Claude-Session: https://claude.ai/code/session_01W8wX9ho5zsL4nSkjw8ZJSM

- Reorder nav to Home/Guide/Reference/Journal, right-align Journal tab

Guide is the actual deliverable, so it leads; Journal is supplementary
raw notes, so it's visually separated on the right rather than mixed
into the primary nav group.

Claude-Session: https://claude.ai/code/session_01W8wX9ho5zsL4nSkjw8ZJSM

- Drop the right-align CSS, keep Journal in normal tab flow

Claude-Session: https://claude.ai/code/session_01W8wX9ho5zsL4nSkjw8ZJSM

