# Verified via a real node termination (see guide/runbooks/node-replacement.md) that the
# server-side Vault defaults leave a dead voter's Raft peer entry lingering after Autopilot
# demotes it - cleanup_dead_servers defaults to false, and the HVD module doesn't override it.
# min_quorum must be set for cleanup_dead_servers to take effect; 3 matches this cluster's
# actual node count (terraform/vault's asg_node_count), not a guess.
resource "vault_raft_autopilot" "config" {
  cleanup_dead_servers = true
  min_quorum           = 3
}
