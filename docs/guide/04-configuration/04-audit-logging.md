# Audit logging (CloudWatch)

## Goal

Vault's audit devices record every request and response — the actual compliance-grade trail,
distinct from the KV/AWS auth/dynamic-secrets features covered so far. Enabled one, then
shipped it somewhere durable and queryable instead of leaving it on local disk.

## Steps

1. Enabled a `file` audit device (`vault_audit` resource,
   `terraform/vault-config/audit-logging.tf`) at `/var/log/vault/audit.log` — the path the HVD
   module already provisions and owns correctly via its `vault_dir_logs` variable, no extra
   disk/permissions work needed.
2. Vault has no native "ship to CloudWatch" option — only `file`, `syslog`, and `socket` audit
   devices. Getting the file's contents into CloudWatch Logs needed the AWS CloudWatch Agent,
   installed and configured on the Vault nodes.
3. Considered baking the agent install into the HVD module's own node bootstrap via its
   `custom_startup_script_template` variable — rejected once actually checked: that variable
   **replaces** the module's entire built-in install script rather than extending it, so using
   it would mean reimplementing Vault's own install logic from scratch just to add one extra
   package. Not worth the risk to a working cluster.
4. Used **AWS Systems Manager State Manager** instead — two `aws_ssm_association` resources
   (`AWS-ConfigureAWSPackage` to install the agent, `AmazonCloudWatch-ManageAgent` to configure
   and start it from an `aws_ssm_parameter` holding its JSON config) targeting instances by the
   `aws:autoscaling:groupName` tag the ASG already propagates. Zero changes to the HVD module
   or the launch template, and it automatically covers any future instance the ASG launches,
   not just the ones running today.
5. Added `logs:CreateLogStream`/`PutLogEvents`/`DescribeLogStreams` (scoped to the one new log
   group) and `ssm:GetParameter` (scoped to the one config parameter) to the Vault nodes'
   existing role — same "extra inline policy on `vault-role` from this state" pattern as the
   [dynamic secrets](03-dynamic-aws-secrets.md) `sts:AssumeRole` grant.
6. **Verified with real log data, not just "the association succeeded"** — generated actual
   Vault activity, then read it back from CloudWatch Logs directly. Confirmed sensitive fields
   (`client_token`, `accessor`, etc.) were automatically HMAC-hashed by Vault's own audit
   device, not sent in the clear — audit logs record *that* an action happened and by whom,
   not usable secret material.

## A real ordering bug, caught by checking the association's actual execution status

The two SSM associations applied cleanly on the Terraform side (`depends_on` ordered their
*creation*), but the **install** and **configure** associations still raced on the instance
itself: `describe-association-executions` showed configure failing with "CloudWatch Agent not
installed" seconds after install had already reported success. `depends_on` only orders
Terraform's API calls, not State Manager's own execution timing, which isn't coupled to that at
all. Fixed by re-triggering the configure association by hand once install had actually
finished (`aws ssm start-associations-once`), and added a 30-minute recurring
`schedule_expression` on it going forward, so a genuinely new instance that loses the same race
self-heals instead of silently never shipping logs.

## Gotchas

- The HVD module's `custom_startup_script_template` variable *replaces* the entire built-in
  node install script, it doesn't extend it — not a safe place to bolt on one extra package
  install.
- `depends_on` between two `aws_ssm_association` resources only orders their creation in
  Terraform's API calls — it says nothing about the order State Manager actually executes them
  on an instance. A recurring `schedule_expression` is what actually makes a dependent
  association self-heal after losing that race.

## References

- [Audit Devices (Vault docs)](https://developer.hashicorp.com/vault/docs/audit)
- [AWS Systems Manager State Manager (AWS docs)](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-state.html)
- [Verify audit logging (runbook)](../../runbooks/audit-logging.md)
