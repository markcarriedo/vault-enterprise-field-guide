# Vault Enterprise on AWS EC2 — Field Guide

**Read it: <https://markcarriedo.github.io/vault-enterprise-field-guide/>**

A field guide for installing and configuring [HashiCorp Vault Enterprise](https://www.hashicorp.com/products/vault)
on AWS, starting on EC2. Kept current as each stage of the build is done and validated.

- **[Guide](docs/guide/index.md)** — the numbered how-to: planning, AWS infra, install,
  config, storage, auto-unseal, TLS, clustering/HA, operations, troubleshooting
- **[Reference](docs/reference/architecture.md)** — architecture, an ADR-style decision log,
  and a glossary
- **[Journal](docs/journal/index.md)** — dated field notes, the story behind each part of the
  guide

[`CHANGELOG.md`](CHANGELOG.md) at the repo root is a separate, repo-level artifact — not part
of the published site, and deliberately mechanical (one line per commit, no reasoning) so it
doesn't duplicate the journal.

The site is built with [MkDocs](https://www.mkdocs.org) + Material and deployed to GitHub Pages
via Actions on every push to `main` (see `.github/workflows/deploy-docs.yml`).

## Commit messages, the changelog, and the journal

Commits follow [Conventional Commits](https://www.conventionalcommits.org)
(`type(scope): summary`) — [`CHANGELOG.md`](CHANGELOG.md) is generated from these via
[git-cliff](https://git-cliff.org). The changelog itself renders **summary lines only**,
deliberately terse and mechanical; the narrative "why" behind a change belongs in
[`docs/journal/`](docs/journal/index.md) instead, not the commit body — keeping the two from
overlapping. See [`cliff.toml`](cliff.toml) for how message types map to changelog sections,
and the [decision log](docs/reference/decisions.md) for the full history of this back-and-forth.

`CHANGELOG.md` is committed, but kept in sync automatically — a `post-commit` hook
(`scripts/update-changelog.sh`, wired up via `pre-commit`, see below) regenerates it after
every commit and amends the result straight in if anything changed. Requires `git-cliff`
installed locally:

```bash
brew install git-cliff
```

## Running the site locally

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/mkdocs serve
```

Then open <http://127.0.0.1:8000>.

## Git hooks

This repo uses [pre-commit](https://pre-commit.com) for two hooks: [gitleaks](https://github.com/gitleaks/gitleaks)
(blocks commits containing credentials, keys, or tokens) and the changelog auto-update above.
One install sets up both hook types (`pre-commit` and `post-commit`):

```bash
brew install pre-commit
pre-commit install
```
