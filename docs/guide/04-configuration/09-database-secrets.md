# Database secrets engine (dynamic Postgres credentials)

## Goal

The [AWS secrets engine](03-dynamic-aws-secrets.md)'s pattern applied to a real database —
Vault generates a short-lived Postgres role on demand instead of an app holding a static
connection string forever. Needed genuinely new infrastructure for this one: a small RDS
Postgres instance (`terraform/vault-config/database.tf`), the first feature in this build with
an ongoing AWS cost beyond what was already running.

## Steps

1. `aws_db_instance` (`db.t4g.micro`, Postgres 17.11 — confirmed available in this region
   before pinning it, same discipline as the Vault version pin) in the existing private
   subnets, security group restricted to inbound 5432 from only the Vault nodes (connection
   management) and the demo client (actually using issued credentials) — looked up by name via
   `data "aws_security_group"`, the same pattern `data "aws_iam_role" "vault_node"` already
   established.
2. A `database` mount through the existing generic YAML pattern, then a
   `vault_database_secret_backend_connection` (`verify_connection = true` by default — Vault
   actually connects and authenticates at apply time, not just saving unverified config) and a
   `vault_database_secret_backend_role` scoped to `inventory-service`, TTLs of 5m/1h — short
   enough to make "on demand, not static" something this sandbox can actually demonstrate.
3. **A real bug, not a hypothetical one**: the standard-looking revocation statements
   (`REASSIGN OWNED BY ... TO vaultroot; DROP OWNED BY ...; DROP ROLE ...`) failed outright on
   RDS with `permission denied to reassign objects` — RDS's master user isn't a true Postgres
   superuser, and `REASSIGN OWNED BY` needs the executing role to either be superuser or a
   member of the role being reassigned. Fixed by adding `GRANT "{{name}}" TO vaultroot;` to
   `creation_statements`, so the master user is already a member of every role it creates.
4. **Verified from the app's own identity, not root, including revocation actually working** —
   connected to the real RDS instance with app-issued credentials and ran a real query, then
   revoked the lease as an operator (`-sync`, not the default async revoke — see the gotcha
   below) and confirmed the exact same credentials genuinely stopped working, cross-checked
   directly against `pg_roles` as the master user. Rotated the connection's root credential
   afterward and confirmed `terraform plan` showed zero drift immediately after — the
   provider's `password` field is write-only and never read back from Vault, so a rotated
   credential can't be silently reverted by a future apply.

## Gotchas

- `vault lease revoke <lease_id>` defaults to asynchronous revocation (HTTP 202, queued) — a
  connection test run immediately after can still succeed, which looks like a failed
  revocation when it's really just not finished yet. Use `-sync` when the next step depends on
  the credential actually being gone.
- RDS's master user is not a true PostgreSQL superuser, so the commonly-shown `REASSIGN OWNED
  BY` revocation pattern fails with `permission denied to reassign objects` unless
  `creation_statements` also grants the newly-created role to the master user (`GRANT
  "{{name}}" TO <master>;`) at creation time.

## References

- [Database Secrets Engine (Vault docs)](https://developer.hashicorp.com/vault/docs/secrets/databases)
- [PostgreSQL Database Secrets Engine (Vault docs)](https://developer.hashicorp.com/vault/docs/secrets/databases/postgresql)
- [Test dynamic database credentials (runbook)](../../runbooks/database-credentials.md)
