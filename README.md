# Vault Enterprise on AWS EC2 — Field Guide

A field guide for installing and configuring [HashiCorp Vault Enterprise](https://www.hashicorp.com/products/vault)
on AWS, starting on EC2. Written as we go: a dated journal of what actually happened, plus a
distilled reference guide kept current as each stage of the build is done and validated.

- **[Journal](docs/journal/index.md)** — field notes in the order things happened
- **[Guide](docs/guide/index.md)** — the numbered how-to: planning, AWS infra, install,
  config, storage, auto-unseal, TLS, clustering/HA, operations, troubleshooting
- **[Reference](docs/reference/architecture.md)** — architecture, an ADR-style decision log,
  and a glossary

The site is built with [MkDocs](https://www.mkdocs.org) + Material — see below for running it
locally.

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
