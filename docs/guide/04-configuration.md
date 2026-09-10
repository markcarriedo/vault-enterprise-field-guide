# Configuration

## Goal

Configure actual Vault features on top of the running cluster — starting with static
secrets, then whatever comes next (dynamic secrets, PKI, auth methods, policies for real
workloads). One page for now; if this grows past 2-3 distinct features, it'll split into a
nested `04-configuration/` section per feature rather than staying one long page.

## Static secrets (KV v2)

### Steps

1. Enabled the KV v2 secrets engine at the standard `secret/` path:
   `vault secrets enable -path=secret -version=2 kv`. Nothing was pre-mounted — `operator
   init` doesn't enable any secrets engines by default (that's only `vault server -dev`).
2. Wrote and read a test secret (`secret/field-guide/hello`), confirmed KV v2's versioning
   works as expected — a second `vault kv put` correctly created version 2 without
   overwriting version 1's history.
3. Wrote a least-privilege policy (`field-guide-app`) scoped to read/list only, only under
   `secret/data/field-guide/*` and `secret/metadata/field-guide/*` — the pattern an
   application would actually use, not the root token.
4. **Verified enforcement, not just existence** — created a short-lived token scoped to that
   policy and confirmed: it *can* read the secret it's meant to; it *cannot* write to that
   same path (403); it *cannot* read an unrelated path (403). Revoked the test token
   immediately after.

### Path convention

Secrets live under `secret/<team-or-app>/...` — see
[Patterns: multi-team static secrets](../reference/patterns.md) for when this simple
convention is enough versus when separate mounts or Namespaces are worth the extra
complexity. For one app in a sandbox, plain path-based policy is the right amount of
structure; it won't stay that way forever.

## Vault config as code

The mount and policy above were created by hand with the CLI first, to move fast and verify
behavior interactively. Once they were working, they moved into `terraform/vault-config/`
using the [`hashicorp/vault`](https://registry.terraform.io/providers/hashicorp/vault/latest)
provider — the same pattern already used for the AWS infrastructure, applied to Vault's own
internal configuration.

Both were brought under management with `terraform import` rather than recreated, then
verified with `terraform plan` showing zero drift before anything else was touched — proof
the Terraform config exactly describes what's actually running, not a guess at it. See
[Decision log](../reference/decisions.md) for why this moved to Terraform instead of staying
as tracked-but-manual CLI commands.

The provider takes no credentials in its config block — like the AWS provider elsewhere in
this repo, it reads `VAULT_ADDR`, `VAULT_TOKEN`, `VAULT_CACERT`, and `VAULT_TLS_SERVER_NAME`
from the environment, supplied fresh each session after the [SSM tunnel](05-operations.md)
is up. Nothing is hardcoded or persisted to disk.

### Adding a mount or policy

`main.tf` doesn't declare resources directly — it loops over `vault-config.yaml` with
`for_each`:

```yaml
mounts:
  secret:
    type: kv
    description: "Static secrets (KV v2) - see guide/04-configuration.md"
    options:
      version: "2"

policies:
  field-guide-app:
    policy_file: field-guide-app.hcl
```

To add another mount or policy, add an entry to the YAML (and a `.hcl` file under
`policies/` for a new policy) — `main.tf` itself only changes when a genuinely new *kind*
of resource needs managing (an auth method, say), not for every new mount or policy.

## AWS auth method

### Goal

Stop using the root token for routine work. The `field-guide-app` policy already existed;
what was missing was a way for something *other than a human with the root token* to get a
token scoped to it.

### Steps

1. Considered AppRole first, the more commonly-documented option — rejected for this build
   specifically: AppRole's `secret_id` needs a trusted distributor (CI/CD, an orchestrator)
   to vend it safely, and this repo deliberately has none (`terraform` runs locally only, no
   pipeline — see decision log). Response-wrapping the `secret_id` by hand defeats the point
   of automating auth in the first place.
2. Used the **AWS auth method** instead: an EC2 instance authenticates using its own IAM
   role identity (a signed STS `GetCallerIdentity` request) — no `secret_id`, nothing to vend
   or leak, since the credential *is* the instance's already-existing IAM role.
3. Added `vault_auth_backend`, `vault_aws_auth_backend_client`, and
   `vault_aws_auth_backend_role` to `terraform/vault-config/auth.tf` — bound to the Vault
   nodes' own IAM role (looked up by name via a Terraform data source, not by ARN, so the
   AWS account ID never appears literally in a committed file), `token_policies =
   ["field-guide-app"]`, `auth_type = "iam"`. There's no separate "app" instance in this
   sandbox, so a Vault node's own role doubles as the client proving the pattern end-to-end.
4. **Verified end-to-end from the instance itself** — IAM-based login only works when the
   *caller* signs its own request, so this couldn't be tested from a laptop; had to SSM onto
   a Vault node and run `vault login -method=aws role=field-guide-app` there. Succeeded on
   the first try: token came back with `["default", "field-guide-app"]` policies attached,
   no manual token creation involved. Same rigor as the KV v2 policy: read the secret it's
   scoped to (succeeded), write to that same path (403), read an unrelated path (403).

### Why AWS auth over AppRole here

AppRole's model assumes something trusted already exists to hand out `secret_id`s safely
(response-wrapped, over CI, etc.) — this repo has no such automation by design. AWS auth
sidesteps the problem instead of solving it: the credential is the instance's IAM role,
already scoped by IAM, already rotated by AWS, nothing new to distribute. See
[decision log](../reference/decisions.md) for the full comparison.

## Gotchas

- `operator init` does not enable any secrets engines — `secret/` (or any other KV mount)
  has to be created explicitly. Only `-dev` mode auto-mounts one.
- Testing a policy by reading it isn't enough — a policy that *parses* isn't the same as a
  policy that *enforces* correctly. Always test with an actual token scoped to it, not the
  root token, before trusting it.
- AWS IAM-type auth can't be tested from a machine other than the one authenticating — the
  login request has to be signed by the caller's own credentials. Testing from a laptop with
  different AWS credentials just proves the *wrong* identity can't log in, not that the right
  one can.

## References

- [KV Secrets Engine v2 (Vault docs)](https://developer.hashicorp.com/vault/docs/secrets/kv/kv-v2)
- [Policies (Vault docs)](https://developer.hashicorp.com/vault/docs/concepts/policies)
- [AWS Auth Method (Vault docs)](https://developer.hashicorp.com/vault/docs/auth/aws)
- [Patterns: multi-team static secrets](../reference/patterns.md)
