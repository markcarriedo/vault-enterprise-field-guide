# Raft snapshot storage

## Goal

Integrated Storage's disaster-recovery story needs a durable place to land Raft snapshots and a
proven procedure for using them — not just the theoretical existence of `vault operator raft
snapshot save`/`restore`.

## Steps

1. Added a dedicated S3 bucket (`aws_s3_bucket.vault_snapshots`,
   `terraform/vault-config/snapshots.tf`) — same security pattern already proven out for the
   Terraform state bucket: versioning enabled, KMS SSE with a bucket key, all public access
   blocked, an explicit `DenyInsecureTransport` bucket policy, and a 30-day lifecycle
   expiration on both current and noncurrent versions.
2. Considered Vault Enterprise's own automated snapshot agent instead of a manual flow —
   rejected for now: it needs its own IAM grant on the Vault nodes' role plus a Vault-API-side
   configuration this Terraform provider has no dedicated resource for, more machinery than
   proving the core save/restore mechanism actually needs.
3. The actual save/upload/restore runbook lives in
   [Backup and restore a Raft snapshot](../../runbooks/raft-snapshot-backup-restore.md) rather
   than here — this page covers the durable storage it depends on, not the day-to-day
   procedure.
4. **Verified with a real, safe round-trip test, not just a successful command exit code** —
   wrote a disposable marker key *after* taking a snapshot, restored that snapshot, then
   confirmed the marker was gone (proof the restore genuinely reloaded state) while data
   written *before* the snapshot survived untouched. Checked cluster health (`vault operator
   raft list-peers`) before and after — identical three-node topology, same leader, same
   Cluster ID, both times.

## Gotchas

- `vault operator raft snapshot save` writes to wherever the CLI runs, not to the Vault
  server — there's no file to go looking for on a node afterward.
- A Raft snapshot restore reloads state cluster-wide; anything written after the snapshot was
  taken is gone once it completes. A disposable, timestamped marker key written *after* the
  snapshot is a reliable way to prove a restore actually did something, versus re-checking
  already-known-good data (which would look identical whether the restore worked or was a
  silent no-op).

## References

- [`operator raft` command (Vault docs)](https://developer.hashicorp.com/vault/docs/commands/operator/raft)
- [Backup and restore a Raft snapshot (runbook)](../../runbooks/raft-snapshot-backup-restore.md)
