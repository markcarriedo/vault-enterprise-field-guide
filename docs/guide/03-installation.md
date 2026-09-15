# Installing Vault Enterprise

## Goal

Deploy Vault Enterprise onto the prerequisites from the previous step, using HashiCorp's HVD
module, then get the cluster from "resources exist" to "initialized, unsealed, and actually
serving traffic."

## Steps

1. **Wire up the module.** `terraform/vault/main.tf` calls `hashicorp/vault-enterprise-hvd/aws`
   `~> 0.4`, reading every input from `terraform/prerequisites`' state via
   `data.terraform_remote_state` — no ARNs copy-pasted by hand. Deliberate overrides from the
   module's defaults: `asg_node_count = 3` (not 6 — standard Raft HA quorum minimum),
   `ec2_allow_ssm = true` (no bastion host), `net_ingress_lb_cidr_blocks` restricted to the
   VPC's own CIDR, `route53_vault_hosted_zone_is_private = true` (the module's Route53 lookup
   defaults to public-zone semantics and fails against a private zone without this).
2. **`terraform apply`.** 19 resources, all created cleanly — ASG, launch template, internal
   NLB, target group, security groups, IAM role/instance profile, Route53 alias record.
3. **Discover it doesn't actually work.** Terraform succeeding is not the same as Vault
   working. All 3 nodes crash-looped. Diagnosed via SSM (`ec2_allow_ssm` paid off
   immediately): `systemctl status vault` → exit 1, `journalctl -u vault` → the real error,
   `license validation failed: invalid module: "platform-standard"`. The module's default
   `vault_version` (`1.17.3+ent`) didn't match what our license actually entitles.
4. **Fix it.** Confirmed `2.1.0+ent` was a real, published release
   (`releases.hashicorp.com/vault/index.json`) before pinning `vault_version` to it — didn't
   want to guess a version string against a live account. Applied (updates the launch
   template's rendered install script), then `aws autoscaling start-instance-refresh` to
   actually roll the already-running nodes — a launch template change alone doesn't touch
   them.
5. **Validate.** All 3 targets went `healthy` in the target group; `vault status` via SSM
   confirmed `active`, `2.1.0+ent`, `awskms` seal, `Initialized: false` / `Sealed: true` —
   exactly the expected pre-init state.
6. **Initialize and unseal.** SSM port-forward straight to a node's own 8200 (no bastion —
   the access pattern this was built for). `vault operator init -format=json`, piped directly
   into a new Secrets Manager secret, local copy shredded — the root token and recovery key
   shares never touched disk persistently or appeared in full anywhere. Auto-unseal via KMS
   kicked in immediately; `vault operator raft list-peers` confirmed all 3 nodes as voters (1
   leader, 2 followers).
7. **Swap to an approved AMI, live.** The module's own default AMI lookup (Canonical's public
   Ubuntu 22.04) got flagged by IBM security. `terraform/vault/data.tf` looks up the latest
   internally-published `hc-base-ubuntu-2204-*` and passes it to the module's `vm_image_id`
   override — same OS/version, different (approved) publisher, so nothing else about the
   module's behavior changes. Applied in two deliberate stages: the launch template update
   alone first (confirmed via `terraform plan` it only updates `image_id` in place, doesn't
   touch running instances — same class of gotcha as the version-pin fix above), then a real
   ASG instance refresh (`MinHealthyPercentage: 66`, explicit rather than the default, so at
   least 2 of 3 nodes stay up throughout) to actually replace the 3 running nodes. Verified
   real Raft state through the whole rollout, not just the ASG's own status — see the
   [decision log](../reference/decisions.md) for what that caught.

## Gotchas

- SSM **port-forwarding** (`aws ssm start-session`) needs the `session-manager-plugin`
  binary installed separately from the `aws` CLI itself — `brew install --cask
  session-manager-plugin`. Plain `ssm send-command` (used for the diagnostics above) doesn't
  need it, which is why this wasn't caught until actually tunneling to run `operator init`.
- The module's Route53 zone lookup silently assumes a **public** zone —
  `route53_vault_hosted_zone_is_private = true` is required for a private zone, or you get
  "no matching Route 53 Hosted Zone found" even though the zone obviously exists.
- Updating the launch template doesn't touch **already-running** ASG instances — needs a
  separate `aws autoscaling start-instance-refresh` to actually roll them.
- `vault status` returns a non-zero exit code when the cluster is sealed — that's the CLI's
  normal convention, not a failure.
- An ASG instance refresh replaces nodes one at a time by default, but trust the *default*
  minimum-healthy setting carefully on a 3-node Raft cluster — an explicit
  `MinHealthyPercentage` states outright how many nodes must stay up, rather than hoping the
  default happens to preserve quorum.
- After each node cycles through an instance refresh, its old Raft peer entry lingers as a
  demoted (non-voter) but not-removed entry — the same Autopilot behavior documented in
  [node replacement](../runbooks/node-replacement.md), now hit once per replaced node instead
  of once. `vault operator raft remove-peer` on each old ID is still a manual step.

## References

- [terraform-aws-vault-enterprise-hvd (GitHub)](https://github.com/hashicorp/terraform-aws-vault-enterprise-hvd)
- [hashicorp/vault-enterprise-hvd/aws (Terraform Registry)](https://registry.terraform.io/modules/hashicorp/vault-enterprise-hvd/aws/latest)
- [Port forwarding using Session Manager (AWS docs)](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-port-forwarding.html)
- [EC2 Auto Scaling instance refresh (AWS docs)](https://docs.aws.amazon.com/autoscaling/ec2/userguide/asg-instance-refresh.html)
- [Decision log](../reference/decisions.md) — the license/version fix, how the init output
  was secured, and the approved-AMI swap
