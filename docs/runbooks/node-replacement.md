# Recover from a lost Vault node

What actually happens when a Raft node dies and the ASG replaces it — verified by terminating
a real, healthy follower in the live cluster and watching the recovery through to a clean
3-voter cluster again. This is a genuinely disruptive test against live infrastructure (Raft
tolerates the loss fine with 3 nodes, but it's still a real termination), so treat it
deliberately, not as a routine check.

```bash
# 1. Fresh AWS credentials, then confirm cluster health and Autopilot config
#    before touching anything - Autopilot's cleanup_dead_servers defaults to
#    false, and this build doesn't turn it on, so a dead voter needs manual
#    cleanup rather than disappearing on its own
vault operator raft list-peers
vault operator raft autopilot get-config
```

```bash
# 2. Terminate a follower (not the leader, to minimize disruption) via the
#    ASG's own termination API - this decrements nothing and triggers an
#    immediate replacement, unlike a raw `aws ec2 terminate-instances`
aws autoscaling terminate-instance-in-auto-scaling-group \
  --instance-id <follower-instance-id> \
  --no-should-decrement-desired-capacity
```

```bash
# 3. Watch Raft directly, not just the ASG - the ASG's health check is
#    EC2-level only and can't tell whether Vault itself ever started
vault operator raft list-peers
# the dead node's entry lingers with Voter=false (Autopilot demotes it
# automatically) until it's explicitly removed in step 5
```

```bash
# 4. If the new instance's bootstrap fails silently (ASG still shows
#    "Healthy" - it only checks EC2 status, not Vault), check further before
#    assuming it's just slow:
aws ssm send-command --instance-ids <new-instance-id> \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["cloud-init status","systemctl is-active vault","tail -30 /var/log/cloud-init-output.log"]'
# a failed `apt-get install` here almost always means the dpkg lock was held
# by `unattended-upgrades` at boot - a timing race, not a real config problem.
# Terminate the broken instance the same way as step 2 and let the ASG retry.
```

```bash
# 5. Once the replacement genuinely joins as a voter, remove the dead peer's
#    now-stale entry - it won't clean itself up
vault operator raft remove-peer <dead-node-instance-id>
vault operator raft list-peers
# expect exactly 3 voters again, all real, healthy nodes
```

```bash
# 6. Confirm nothing else was affected
vault status
vault operator raft autopilot state
vault kv get -field=message secret/inventory-service/hello
```

Verified end-to-end on this cluster: a terminated follower's Raft entry was auto-demoted to
non-voter within seconds, but never auto-removed. The first replacement instance's bootstrap
actually failed silently - a `dpkg` lock race with `unattended-upgrades` broke its
`apt-get install`, and the ASG kept reporting it "Healthy" the entire time since it only checks
EC2-level status. Terminating that broken instance and letting the ASG retry succeeded cleanly:
the second replacement installed Vault, joined Raft as a non-voter, and was auto-promoted to
voter within about 15 seconds. `raft remove-peer` on the original dead node's ID brought the
cluster back to exactly 3 real voters, same leader, same Cluster ID, unaffected throughout.

## Gotchas

- Autopilot's `cleanup_dead_servers` defaults to `false`, and the HVD module doesn't set it.
  A dead voter gets demoted to non-voter automatically, but its Raft peer entry stays until a
  manual `vault operator raft remove-peer`. Left unaddressed across repeated node losses, stale
  entries accumulate and quietly erode real fault tolerance even though `list-peers` still
  shows the cluster as "healthy."
- The ASG's own health check is EC2-status-only - it cannot tell whether Vault itself ever
  started. A node that fails partway through its install script can sit there reporting
  "Healthy" indefinitely. Trust `vault operator raft list-peers`/`autopilot state` over ASG
  console state when verifying a replacement actually worked.
- A `dpkg`/`apt-get` lock failure during a fresh Ubuntu instance's boot (`unattended-upgrades`
  running its own apt job at the same moment cloud-init's user-data script does) is a timing
  race, not a real misconfiguration - it doesn't reliably reproduce, and terminating the broken
  instance to let the ASG try again is a legitimate, sufficient recovery step.
- Each `aws autoscaling terminate-instance-in-auto-scaling-group` call is a real, live action
  against production-like infrastructure and should be treated with the same care as any other
  destructive operation in this build - confirm cluster health before and after, and don't
  chain terminations without checking Raft state in between.

## References

- [Vault Integrated Storage Autopilot (Vault docs)](https://developer.hashicorp.com/vault/docs/concepts/integrated-storage/autopilot)
- [`operator raft` command (Vault docs)](https://developer.hashicorp.com/vault/docs/commands/operator/raft)
- [Terminate instance in Auto Scaling group (AWS docs)](https://docs.aws.amazon.com/autoscaling/ec2/userguide/as-instance-termination.html)
