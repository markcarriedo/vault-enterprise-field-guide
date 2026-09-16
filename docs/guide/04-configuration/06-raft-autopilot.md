# Raft Autopilot

## Goal

Autopilot governs how the cluster handles a lost node — whether a dead voter's Raft peer entry
cleans itself up, and how strict that cleanup is. Left at Vault's raw defaults, that's a real
gap: a manual step every time, discovered the hard way in
[Recover from a lost Vault node](../../runbooks/node-replacement.md).

## Steps

1. Added `vault_raft_autopilot.config` (`terraform/vault-config/autopilot.tf`) —
   `cleanup_dead_servers = true`, `min_quorum = 3` (this cluster's real node count). The
   `hashicorp/vault` provider has had this resource for a while; nothing here needed it until
   the node-replacement test surfaced the gap it closes.
2. **Verified, and the verification changed what got documented** — re-ran the exact same
   node-termination test expecting the dead peer to vanish automatically once the replacement
   joined. It didn't, within several minutes. `dead_server_last_contact_threshold` (still the
   24h default — HashiCorp recommends against lowering it) is the actual gate on removal, not
   `cleanup_dead_servers` alone. The Terraform change is real and worth keeping, but the
   runbook's manual `remove-peer` step is still required for a prompt cleanup.

## Gotchas

- `cleanup_dead_servers = true` doesn't make Autopilot prune a dead Raft peer promptly —
  removal only happens after `dead_server_last_contact_threshold` (24h by default) of
  continuous unreachability. A config flag named after the behavior you want doesn't guarantee
  it happens on the timescale you assume; verified by repeating the exact same node-termination
  test after enabling it and watching the dead peer *not* disappear within several minutes.

## References

- [Vault Integrated Storage Autopilot (Vault docs)](https://developer.hashicorp.com/vault/docs/concepts/integrated-storage/autopilot)
- [Recover from a lost Vault node (runbook)](../../runbooks/node-replacement.md)
