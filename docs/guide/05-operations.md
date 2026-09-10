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

## Gotchas

- The root token from `operator init` works fine for sandbox testing, but reach for real auth
  methods/policies once those exist rather than making root-token use a habit.
- `/tmp/vault-ca.pem` is a throwaway local copy for the session — not sensitive on its own (a
  CA *certificate*, not a private key), but no reason to leave it lying around either.

## References

- [Port forwarding using Session Manager (AWS docs)](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-port-forwarding.html)
- [Architecture](../reference/architecture.md) — the access path this runbook uses
