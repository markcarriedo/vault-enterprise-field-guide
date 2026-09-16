# Configuration

## Goal

Configure actual Vault features on top of the running cluster — starting with static secrets,
then whatever came next. This used to be one long page; once it grew past the 2-3 features it
started with, it split into this section, one page per feature, matching the pattern already
used for [Runbooks](../../runbooks/index.md).

1. [Static secrets (KV v2)](01-static-secrets.md)
2. [AWS auth method](02-aws-auth.md)
3. [Dynamic secrets (AWS secrets engine)](03-dynamic-aws-secrets.md)
4. [Audit logging (CloudWatch)](04-audit-logging.md)
5. [Raft snapshot storage](05-raft-snapshots.md)
6. [Raft Autopilot](06-raft-autopilot.md)
7. [Transit (encryption as a service)](07-transit.md)
8. [PKI (Vault as a certificate authority)](08-pki.md)
9. [Database secrets engine (dynamic Postgres credentials)](09-database-secrets.md)

## Vault config as code

The mount and policy for the first feature (static secrets) were created by hand with the CLI
first, to move fast and verify behavior interactively. Once working, they moved into
`terraform/vault-config/` using the
[`hashicorp/vault`](https://registry.terraform.io/providers/hashicorp/vault/latest) provider —
the same pattern already used for the AWS infrastructure, applied to Vault's own internal
configuration. Every feature after that went straight into Terraform from the start.

Both were brought under management with `terraform import` rather than recreated, then verified
with `terraform plan` showing zero drift before anything else was touched — proof the Terraform
config exactly describes what's actually running, not a guess at it. See
[Decision log](../../reference/decisions.md) for why this moved to Terraform instead of staying
as tracked-but-manual CLI commands.

The provider takes no credentials in its config block — like the AWS provider elsewhere in this
repo, it reads `VAULT_ADDR`, `VAULT_TOKEN`, `VAULT_CACERT`, and `VAULT_TLS_SERVER_NAME` from the
environment, supplied fresh each session after the
[SSM tunnel](../../runbooks/connect-manually.md) is up. Nothing is hardcoded or persisted to
disk.

### Adding a mount or app

`main.tf`/`auth.tf`/`dynamic-secrets.tf` don't declare per-app resources directly — they loop
over `vault-config.yaml` with `for_each`. Mounts are infrastructure-level and live at the top;
everything specific to one app (its policy, its AWS auth role, its AWS secrets role) is nested
under that app's own entry, since all three would otherwise repeat the same name as separate
top-level maps:

```yaml
mounts:
  secret:
    type: kv
    description: "Static secrets (KV v2) - see guide/04-configuration/01-static-secrets.md"
    options:
      version: "2"

apps:
  inventory-service:
    policy_file: inventory-service.hcl

    aws_auth:
      token_policies:
        - inventory-service

    aws_secret:
      default_sts_ttl: 900
      max_sts_ttl: 3600
```

An app only needs the sub-keys it actually uses — `aws_auth`/`aws_secret` are optional, so an
app that only needs KV access can omit both. To add another mount or app, add an entry to the
YAML (and a `.hcl` file under `policies/` for a new app's policy) — the `.tf` files themselves
only change for a genuinely new *kind* of resource, not for every new mount or app.

Which AWS IAM principal an app's `aws_auth` trusts, and which IAM role its `aws_secret` is
allowed to assume, are deliberately **not** in this YAML — see
[AWS auth method](02-aws-auth.md) and [Dynamic secrets](03-dynamic-aws-secrets.md) for why.

## References

- [Patterns: multi-team static secrets](../../reference/patterns.md)
- [Decision log](../../reference/decisions.md)
