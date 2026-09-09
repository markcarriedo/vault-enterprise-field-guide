# Glossary

Terms as we encounter them.

| Term | Meaning |
|---|---|
| Seal | The process that protects Vault's encryption key; must be "unsealed" before Vault can operate. |
| Auto-unseal | Delegating unseal to an external KMS (here, AWS KMS) instead of manual key shards. |
| Storage backend | Where Vault persists its encrypted data (e.g. Integrated Storage/Raft, Consul). |
| Integrated Storage | Vault's built-in Raft-based storage backend — no separate Consul cluster needed. |
| HVD | HashiCorp Validated Design — HashiCorp's published reference architectures and Terraform modules for deploying its products in production. |
| Conventional Commits | A commit message convention (`type(scope): summary`, e.g. `docs:`, `feat:`, `fix:`) that tools like git-cliff parse to generate changelogs automatically. |
