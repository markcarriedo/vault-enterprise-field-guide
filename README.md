# Vault Enterprise on AWS EC2 — Field Guide

Source for the MkDocs site documenting the Vault Enterprise on AWS EC2 build.

## Local development

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

## Structure

- `docs/journal/` — dated field notes, written as we go
- `docs/guide/` — the distilled, numbered how-to
- `docs/reference/` — architecture, decision log, glossary
