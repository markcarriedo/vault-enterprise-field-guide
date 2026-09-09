# Journal

Dated field notes from the build, in the order things happened. Newest entries at the top.
For the "why" behind a choice, see the [decision log](../reference/decisions.md) — this page
is the raw play-by-play.

---

## 2026-09-09 — AWS survey: sandbox account, ap-southeast-2

Authenticated to the HashiCorp sandbox account (Doormat-issued STS session, profile
`hc-sandbox`) and settled on `ap-southeast-2` as the working region, matching the existing
personal AWS profiles. Along the way: STS session credentials turned out to *not* be
region-locked — a `describe-vpcs` call succeeded in three different regions on the same
session, disproving an initial (wrong) assumption that the token was scoped to `us-west-2`.

Surveyed the sandbox account/region: only the AWS-managed default VPC (public subnets only,
no NAT gateways) and AWS-managed default KMS keys exist. All four prerequisites for the HVD
module — VPC, KMS key, license in Secrets Manager, TLS material in Secrets Manager — start
from scratch. See [decisions](../reference/decisions.md) and
[Planning & Prerequisites](../guide/01-planning.md).

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

## 2026-09-09 — Journal dropped, then revived

Briefly dropped this journal entirely in favor of treating `docs/guide/` + `docs/reference/`
as the sole published output (reasoning: avoid duplicating raw notes and polished guide
content). Reconsidered — a chronological log alongside the guide is worth keeping. Considered
a GitHub Wiki for it (keeps it fully out of the MkDocs build) but the wiki's git repo can't be
initialized without first creating a page through the GitHub web UI, which doesn't fit an
automated workflow — reverted to keeping the journal here, in `docs/journal/`.

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
