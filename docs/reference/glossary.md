# Glossary

Terms as we encounter them.

| Term | Meaning |
|---|---|
| Seal | The process that protects Vault's encryption key; must be "unsealed" before Vault can operate. |
| Auto-unseal | Delegating unseal to an external KMS (here, AWS KMS) instead of manual key shards. |
| Storage backend | Where Vault persists its encrypted data (e.g. Integrated Storage/Raft, Consul). |
