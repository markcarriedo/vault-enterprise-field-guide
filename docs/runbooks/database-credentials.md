# Test dynamic database credentials

Like the other secrets-engine runbooks, this runs **from the dedicated demo client instance**,
proving the app identity gets real, usable, genuinely revocable Postgres credentials — not
just a successful `vault read`.

```bash
# 1. Fresh AWS credentials, then a real shell on the demo client instance
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=inventory-service-instance" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].InstanceId" --output text)

aws ssm start-session --target "$INSTANCE_ID"
```

```bash
# 2. On the instance: the Postgres client isn't preinstalled
sudo dnf install -y postgresql15

aws secretsmanager get-secret-value \
  --secret-id vault-enterprise/tls-ca-bundle \
  --query SecretString --output text | base64 -d > /tmp/vault-ca.pem

export VAULT_ADDR=https://vault.sandbox.internal:8200
export VAULT_CACERT=/tmp/vault-ca.pem
```

```bash
# 3. Log in via AWS auth, then request dynamic database credentials
export VAULT_TOKEN=$(vault login -method=aws role=inventory-service -format=json | \
  python3 -c "import json,sys; print(json.load(sys.stdin)['auth']['client_token'])")

vault read -format=json database/creds/inventory-service > /tmp/db-creds.json
python3 -c "
import json
d = json.load(open('/tmp/db-creds.json'))
print('username:', d['data']['username'])
print('lease_id:', d['lease_id'])
"
```

```bash
# 4. Prove they're real - connect to the actual RDS instance and run a query
DBUSER=$(python3 -c "import json; print(json.load(open('/tmp/db-creds.json'))['data']['username'])")
DBPASS=$(python3 -c "import json; print(json.load(open('/tmp/db-creds.json'))['data']['password'])")

PGPASSWORD="$DBPASS" psql \
  "host=<rds endpoint> dbname=inventoryservice user=$DBUSER sslmode=require" \
  -c "SELECT current_user, now();"
```

```bash
# 5. (Operator-only, from your laptop with the root token) revoke the lease
#    and confirm the same credentials genuinely stop working - use -sync,
#    not the default async revoke (see the gotcha below)
vault lease revoke -sync <lease_id from step 3>

# rerun step 4's psql command with the same credentials - it now fails with
# "password authentication failed", not just a soft/eventual revocation
```

```bash
# 6. (Operator-only) rotate the root credential Vault uses to manage this
#    connection - after this, nobody, including Terraform, knows the real
#    database master password except Vault itself
vault write -f database/rotate-root/postgres

# confirm Vault's own connection still works post-rotation
vault read database/creds/inventory-service
```

Verified end-to-end: the app identity connected to the real RDS instance with dynamically
issued credentials, ran a real query, and after an operator's synchronous revoke, the exact
same credentials genuinely stopped working - confirmed both by the failed connection and by
directly querying `pg_roles` as the master user to see the role was actually gone. Root
rotation left Vault's own connection working while a `terraform plan` immediately afterward
showed zero drift.

## Gotchas

- `vault lease revoke <lease_id>` defaults to **asynchronous** revocation (`sync:false`, HTTP
  202 "Accepted") - it queues the revocation and returns immediately, without guaranteeing it's
  actually happened yet. A connection test run right after an async revoke can still succeed,
  which looks like revocation failed when it's really just not finished. Use
  `vault lease revoke -sync` when you need to know the credential is actually gone before
  moving on, same rule as everywhere else in this build: don't trust a success message alone.
- RDS's master user is **not a true PostgreSQL superuser** - AWS manages real superuser
  privileges itself. The commonly-shown revocation pattern
  (`REASSIGN OWNED BY "{{name}}" TO <root>; DROP OWNED BY "{{name}}"; DROP ROLE ...`) fails on
  RDS with `permission denied to reassign objects (SQLSTATE 42501)`, because `REASSIGN OWNED BY`
  requires the executing role to be a superuser *or* a member of the role being reassigned. The
  fix: add `GRANT "{{name}}" TO <root>;` to `creation_statements`, so the master user is already
  a member of every role it creates and can legitimately reassign/drop it later. Not documented
  in Vault's own Postgres plugin docs - found by testing revocation for real, not by reading.
- After `database/rotate-root/<connection>`, the real database password is something only
  Vault knows - Vault's API never returns it, and the Terraform provider's `password` field is
  write-only (never read back from Vault), so a stale value in Terraform state can't cause a
  future `apply` to silently overwrite the rotation. Verified directly: `terraform plan`
  immediately after rotating showed zero drift.

## References

- [Database Secrets Engine (Vault docs)](https://developer.hashicorp.com/vault/docs/secrets/databases)
- [PostgreSQL Database Secrets Engine (Vault docs)](https://developer.hashicorp.com/vault/docs/secrets/databases/postgresql)
- [PostgreSQL `REASSIGN OWNED` (PostgreSQL docs)](https://www.postgresql.org/docs/current/sql-reassign-owned.html)
