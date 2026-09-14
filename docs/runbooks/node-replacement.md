# Recover from a lost Vault node

What actually happens when a Raft node dies and the ASG replaces it — verified by terminating
a real, healthy follower in the live cluster and watching the recovery through to a clean
3-voter cluster again. This is a genuinely disruptive test against live infrastructure (Raft
tolerates the loss fine with 3 nodes, but it's still a real termination), so treat it
deliberately, not as a routine check.

```bash
# 1. Fresh AWS credentials, then confirm cluster health and Autopilot config
#    before touching anything. This cluster manages Autopilot config via
#    Terraform (terraform/vault-config/autopilot.tf): cleanup_dead_servers is
#    on, but that alone doesn't make cleanup prompt - see step 5.
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
#    now-stale entry by hand - cleanup_dead_servers being on does NOT make
#    this prompt (see the gotcha below), so don't wait for it
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

Verified end-to-end on this cluster, twice. First pass (Autopilot at Vault's raw defaults,
`cleanup_dead_servers = false`): a terminated follower's Raft entry was auto-demoted to
non-voter within seconds, but never auto-removed. The first replacement instance's bootstrap
also failed silently - a `dpkg` lock race with `unattended-upgrades` broke its
`apt-get install`, and the ASG kept reporting it "Healthy" the entire time since it only checks
EC2-level status. Terminating that broken instance and letting the ASG retry succeeded cleanly:
the second replacement installed Vault, joined Raft as a non-voter, and was auto-promoted to
voter within about 15 seconds. `raft remove-peer` on the original dead node's ID brought the
cluster back to exactly 3 real voters.

Second pass, after turning `cleanup_dead_servers` on via Terraform: repeated the same
termination and expected the dead peer to disappear on its own once the replacement joined.
It didn't - `autopilot state` showed the dead node's `NodeStatus` still `"alive"` (just
`Healthy: false`) more than two minutes after termination. Automatic pruning only fires once a
node crosses `dead_server_last_contact_threshold` (24h by default) - `cleanup_dead_servers`
being on doesn't change that gate. `remove-peer` was still needed by hand. See the decision log
for why the 24h default is correct to keep, not something to lower.

## Gotchas

- A dead voter gets demoted to non-voter automatically regardless of `cleanup_dead_servers`,
  but its Raft peer entry only gets *removed* once the node's Autopilot `NodeStatus` transitions
  from `alive` to `failed` - which requires `dead_server_last_contact_threshold` (24h by
  default) of continuous unreachability, not just a few minutes of being unhealthy. In practice
  this means `cleanup_dead_servers = true` is a long-horizon safety net against forgetting to
  clean up, not a substitute for the manual `remove-peer` step above. HashiCorp's own docs
  explicitly recommend keeping that threshold high (this build left it at the 24h default)
  rather than lowering it, since a short threshold risks pruning a node that's only briefly
  unreachable (a restart, a snapshot load, an HSM delay) - turning a recoverable blip into an
  unnecessary Raft membership change. Left unaddressed across repeated node losses, stale
  entries still accumulate and quietly erode real fault tolerance even though `list-peers`
  keeps showing the cluster as "healthy."
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
