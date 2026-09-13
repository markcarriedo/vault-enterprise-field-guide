# Verify audit logging

Confirm audit logs are actually landing in CloudWatch — not just that the SSM associations
report success (see [the ordering bug](../reference/decisions.md) that made "association
succeeded" alone unreliable). Runs from your laptop; no tunnel needed, since this only talks
to CloudWatch Logs, not Vault directly.

```bash
# 1. Fresh AWS credentials, then generate some real Vault activity first
#    (via the "Connect to the cluster manually" runbook, or reuse an
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

## References

- [CloudWatch Logs CLI reference (AWS docs)](https://docs.aws.amazon.com/cli/latest/reference/logs/)
