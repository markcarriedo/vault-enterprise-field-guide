# Backup and restore a Raft snapshot

A full Raft snapshot capture, upload, and restore — the actual mechanism behind disaster
recovery for Integrated Storage. Run the save/upload from a laptop connected via
[Connect to the cluster manually](connect-manually.md); the restore is a genuinely disruptive,
cluster-wide operation, so treat step 4 as something to run deliberately, not as part of
routine testing.

```bash
# 1. With a tunnel + VAULT_ADDR/VAULT_CACERT/VAULT_TOKEN set up (see "Connect to
#    the cluster manually"), take the snapshot - it streams to wherever
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

- `vault operator raft snapshot save` streams to wherever the CLI runs, not to the server —
  there's no snapshot file sitting on a Vault node afterward to go looking for.
- A restore reloads Raft state cluster-wide; anything written after the snapshot was taken is
  gone once it completes. Confirm which snapshot you're restoring before running it.

## References

- [`operator raft` command (Vault docs)](https://developer.hashicorp.com/vault/docs/commands/operator/raft)
