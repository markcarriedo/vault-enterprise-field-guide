# Vault Enterprise on AWS EC2 — Field Guide

**Read it: <https://markcarriedo.github.io/vault-enterprise-field-guide/>**

A field guide for installing and configuring [HashiCorp Vault Enterprise](https://www.hashicorp.com/products/vault)
on AWS, starting on EC2. Kept current as each stage of the build is done and validated.

- **[Guide](docs/guide/index.md)** — the numbered how-to: planning, AWS infra, install,
  config, storage, auto-unseal, TLS, clustering/HA, operations, troubleshooting
- **[Reference](docs/reference/architecture.md)** — architecture, an ADR-style decision log,
  and a glossary

[`CHANGELOG.md`](CHANGELOG.md) at the repo root is a separate, repo-level artifact — not part
of the published site.

The site is built with [MkDocs](https://www.mkdocs.org) + Material and deployed to GitHub Pages
via Actions on every push to `main` (see `.github/workflows/deploy-docs.yml`).

## Commit messages and the changelog

Commits follow [Conventional Commits](https://www.conventionalcommits.org)
(`type(scope): summary`) — [`CHANGELOG.md`](CHANGELOG.md) is generated from these via
[git-cliff](https://git-cliff.org), so put reasoning in the commit **body**, not just the
summary line. See [`cliff.toml`](cliff.toml) for how message types map to changelog sections,
and the [decision log](docs/reference/decisions.md) for why.

`CHANGELOG.md` is committed, not auto-generated in CI, so regenerate and commit it alongside
any change:

```bash
brew install git-cliff
git-cliff -o CHANGELOG.md
```

## Running the site locally

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/mkdocs serve
```

Then open <http://127.0.0.1:8000>.

## Secret scanning

This repo uses [gitleaks](https://github.com/gitleaks/gitleaks) via [pre-commit](https://pre-commit.com)
to block commits containing credentials, keys, or tokens. After cloning:

```bash
brew install pre-commit
pre-commit install
```
