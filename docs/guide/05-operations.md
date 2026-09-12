# Operations & Runbooks

## Goal

Day-to-day operational procedures for the running cluster — connecting to it, checking on it,
and (later) things like credential rotation or onboarding a new team/app. Unlike the earlier
numbered steps (a one-time build sequence), this page collects standalone runbooks that get
used repeatedly, added to as new operational needs come up.

## Runbooks

### Connect to the cluster manually

For ad-hoc testing or troubleshooting — no bastion host, straight to a node over SSM.

```bash
# 1. Fresh AWS credentials (internal credential broker/however you get them)
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_SESSION_TOKEN=...
export AWS_REGION=ap-southeast-2

# 2. Pick any healthy node and tunnel straight to its Vault port
INSTANCE_ID=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names vault-asg \
  --query "AutoScalingGroups[0].Instances[0].InstanceId" --output text)

aws ssm start-session --target "$INSTANCE_ID" \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["8200"],"localPortNumber":["8200"]}'
# ^ leave this running in its own terminal/tab
```

```bash
# 3. In a second terminal: fetch the CA cert (self-signed, needed for TLS verification)
aws secretsmanager get-secret-value \
  --secret-id vault-enterprise/tls-ca-bundle \
  --query SecretString --output text | base64 -d > /tmp/vault-ca.pem

# 4. Point the Vault CLI at the tunnel
export VAULT_ADDR=https://127.0.0.1:8200
export VAULT_CACERT=/tmp/vault-ca.pem
export VAULT_TLS_SERVER_NAME=vault.sandbox.internal

# 5. Auth as root (fine for sandbox testing; not something to do routinely
#    once real auth methods/policies exist)
export VAULT_TOKEN=$(aws secretsmanager get-secret-value \
  --secret-id vault-enterprise/init-output \
  --query SecretString --output text | python3 -c "import json,sys; print(json.load(sys.stdin)['root_token'])")

vault status
vault secrets list
```

Requires the `session-manager-plugin` binary locally (`brew install --cask
session-manager-plugin`) — see [Installing Vault Enterprise](03-installation.md) for why.

### Test dynamic AWS secrets (AWS auth + AWS secrets engine)

Unlike the runbook above, this has to run **from the dedicated demo client instance**
(`terraform/vault-config/demo-client.tf`), not a Vault node and not your laptop — AWS
IAM-type auth requires the caller to sign its own login request, so this needs a real shell on
the instance whose IAM role is actually bound to the `inventory-service` AWS auth role.

```bash
# 1. Fresh AWS credentials, then a real shell on the demo client instance
#    (not a port-forward - this instance isn't a Vault node, so there's
#    nothing listening on its own 8200 to forward to)
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=inventory-service-instance" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].InstanceId" --output text)

aws ssm start-session --target "$INSTANCE_ID"
```

```bash
# 2. On the instance: fetch the CA cert (it isn't a Vault node, so it has
#    no local copy) and point VAULT_ADDR at the cluster's real in-VPC
#    address, not 127.0.0.1 - there's no local Vault process here
aws secretsmanager get-secret-value \
  --secret-id vault-enterprise/tls-ca-bundle \
  --query SecretString --output text | base64 -d > /tmp/vault-ca.pem

export VAULT_ADDR=https://vault.sandbox.internal:8200
export VAULT_CACERT=/tmp/vault-ca.pem
```

```bash
# 3. Log in via AWS auth, then read dynamic credentials
export VAULT_TOKEN=$(vault login -method=aws role=inventory-service -format=json | \
  python3 -c "import json,sys; print(json.load(sys.stdin)['auth']['client_token'])")

vault read aws/creds/inventory-service
# returns access_key, secret_key, security_token, and a lease_id (900s TTL)
```

```bash
# 4. Prove they're real - export them and call AWS with them
export AWS_ACCESS_KEY_ID=<access_key from step 3>
export AWS_SECRET_ACCESS_KEY=<secret_key>
export AWS_SESSION_TOKEN=<security_token>

aws sts get-caller-identity
# Arn should read assumed-role/vault-dynamic-demo/... - proof it's a real,
# working assumed-role session, not just a successful `vault read`
```

Optional: from your laptop (via a port-forward tunnel to a Vault node, with the root token),
`vault lease revoke <lease_id>`, then rerun step 4's `aws sts get-caller-identity` on the demo
client instance with the *same* exported credentials — it'll still succeed. See the
[gotcha in Configuration](04-configuration.md#a-verified-gotcha-assumed_role-revocation-is-soft)
for why.

### Verify audit logging

Confirm audit logs are actually landing in CloudWatch — not just that the SSM associations
report success (see [the ordering bug](../reference/decisions.md) that made "association
succeeded" alone unreliable). Runs from your laptop; no tunnel needed, since this only talks
to CloudWatch Logs, not Vault directly.

```bash
# 1. Fresh AWS credentials, then generate some real Vault activity first
#    (via the "Connect to the cluster manually" runbook above, or reuse an
#    already-authenticated session)
vault kv get secret/inventory-service/hello
```

```bash
# 2. Confirm each node has a log stream (one per instance)
aws logs describe-log-streams --log-group-name "/vault/audit" \
  --query "logStreams[].logStreamName" --output table
```

```bash
# 3. Read the actual events back - don't just trust the stream exists
aws logs get-log-events --log-group-name "/vault/audit" \
  --log-stream-name "<instance-id from step 2>" \
  --limit 5 --start-from-head --query "events[].message" --output text

# or for a live view:
aws logs tail "/vault/audit" --follow
```

```bash
# 4. The real check - confirm sensitive fields are hashed, not plaintext
aws logs get-log-events --log-group-name "/vault/audit" \
  --log-stream-name "<instance-id>" --limit 1 --query "events[-1].message" --output text \
  | grep -o '"client_token":"[^"]*"'
# should show "client_token":"hmac-sha256:..." - a raw token here means the
# audit device config is wrong, not just a nice-to-have
```

If a brand-new node's stream never appears, the install/configure associations may have hit
the ordering race — check `aws ssm describe-association-executions` for that instance; it
should self-heal within 30 minutes via the recurring schedule, or can be forced immediately
with `aws ssm start-associations-once --association-ids <configure association ID>`.

### Backup and restore a Raft snapshot

A full Raft snapshot capture, upload, and restore — the actual mechanism behind disaster
recovery for Integrated Storage. Run the save/upload from a laptop connected via the manual
connect runbook above; the restore is a genuinely disruptive, cluster-wide operation, so treat
step 4 as something to run deliberately, not as part of routine testing.

```bash
# 1. With a tunnel + VAULT_ADDR/VAULT_CACERT/VAULT_TOKEN set up (see "Connect to
#    the cluster manually" above), take the snapshot - it streams to wherever
#    the CLI runs, not to the server
vault operator raft snapshot save /tmp/vault-snapshot.snap
```

```bash
# 2. Upload it to the durable, versioned S3 bucket (terraform/vault-config/snapshots.tf) -
#    this is a manual step, not Vault Enterprise's own automated snapshot agent (see the
#    decision log for why)
aws s3 cp /tmp/vault-snapshot.snap \
  "s3://vault-enterprise-field-guide-raft-snapshots-<suffix>/$(date -u +%Y-%m-%dT%H-%M-%SZ).snap"
```

```bash
# 3. Confirm cluster health before doing anything destructive
vault operator raft list-peers
# expect 3 healthy voters, one leader
```

```bash
# 4. Restore - this reloads Raft state cluster-wide from the snapshot and is
#    briefly disruptive. Only run this deliberately (a real recovery, or a
#    verified test using a disposable marker key like below), never as a
#    routine check.
aws s3 cp "s3://vault-enterprise-field-guide-raft-snapshots-<suffix>/<snapshot key>" \
  /tmp/vault-snapshot.snap

vault operator raft snapshot restore /tmp/vault-snapshot.snap
```

```bash
# 5. Verify - cluster topology should be identical, and data should match
#    exactly what was in the snapshot (nothing written after the snapshot
#    was taken survives the restore)
vault status
vault operator raft list-peers
```

This was verified end-to-end: write a disposable `secret/inventory-service/restore-test`
marker *after* taking a snapshot, restore that snapshot, then confirm the marker is gone
(proving the restore actually reloaded state) while real data written *before* the snapshot
(`secret/inventory-service/hello`) survives untouched. Cluster topology (same 3 nodes, same
leader, same Cluster ID) was unaffected.

## Gotchas

- The root token from `operator init` works fine for sandbox testing, but reach for real auth
  methods/policies once those exist rather than making root-token use a habit.
- `/tmp/vault-ca.pem` is a throwaway local copy for the session — not sensitive on its own (a
  CA *certificate*, not a private key), but no reason to leave it lying around either.
- AWS IAM-type auth (`vault login -method=aws`) can only be tested from the instance whose
  identity is doing the authenticating — a port-forward tunnel isn't enough, since the login
  request itself has to be signed by the caller's own credentials.
- A 403 from Vault usually just means `VAULT_TOKEN` is unset or stale, not necessarily a real
  permission problem — Vault returns 403 for unauthenticated requests too. Check `echo
  $VAULT_TOKEN` before assuming a policy is wrong.
- `vault operator raft snapshot save` streams to wherever the CLI runs, not to the server —
  there's no snapshot file sitting on a Vault node afterward to go looking for.
- A restore reloads Raft state cluster-wide; anything written after the snapshot was taken is
  gone once it completes. Confirm which snapshot you're restoring before running it.

## References

- [Port forwarding using Session Manager (AWS docs)](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-port-forwarding.html)
- [Architecture](../reference/architecture.md) — the access path this runbook uses
- [CloudWatch Logs CLI reference (AWS docs)](https://docs.aws.amazon.com/cli/latest/reference/logs/)
- [`operator raft` command (Vault docs)](https://developer.hashicorp.com/vault/docs/commands/operator/raft)
