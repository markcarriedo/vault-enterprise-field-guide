# Configuration

## Goal

Configure actual Vault features on top of the running cluster — starting with static
secrets, then whatever comes next (dynamic secrets, PKI, auth methods, policies for real
workloads). One page for now; if this grows past 2-3 distinct features, it'll split into a
nested `04-configuration/` section per feature rather than staying one long page.

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
    description: "Static secrets (KV v2) - see guide/04-configuration.md"
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
allowed to assume, are deliberately **not** in this YAML — see the AWS auth and dynamic
secrets sections below for why.

## Static secrets (KV v2)

### Steps

1. Enabled the KV v2 secrets engine at the standard `secret/` path:
   `vault secrets enable -path=secret -version=2 kv`. Nothing was pre-mounted — `operator
   init` doesn't enable any secrets engines by default (that's only `vault server -dev`).
2. Wrote and read a test secret (`secret/inventory-service/hello`), confirmed KV v2's
   versioning works as expected — a second `vault kv put` correctly created version 2 without
   overwriting version 1's history.
3. Wrote a least-privilege policy (`inventory-service`) scoped to read/list only, only under
   `secret/data/inventory-service/*` and `secret/metadata/inventory-service/*` — the pattern
   an application would actually use, not the root token.
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

## AWS auth method

### Goal

Stop using the root token for routine work. The `inventory-service` policy already existed;
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
3. Added a dedicated, minimal EC2 instance (`terraform/vault-config/demo-client.tf`) as the
   client proving the pattern — not one of the Vault nodes' own roles. A real app shouldn't
   authenticate to Vault as the Vault server itself, so this instance exists purely to *be* a
   distinct IAM identity: no AWS permissions beyond SSM access to reach it for testing.
4. Added `vault_auth_backend`, `vault_aws_auth_backend_client`, and `vault_aws_auth_backend_role`
   to `terraform/vault-config/auth.tf` — bound to that dedicated instance's IAM role
   (looked up by name via a Terraform data source, not by ARN, so the AWS account ID never
   appears literally in a committed file), `token_policies = ["inventory-service"]`,
   `auth_type = "iam"`.
5. **Verified end-to-end from the instance itself** — IAM-based login only works when the
   *caller* signs its own request, so this couldn't be tested from a laptop; had to SSM onto
   the demo client instance and run `vault login -method=aws role=inventory-service` there
   (pointed at the cluster's real in-VPC address, `vault.sandbox.internal:8200` — this
   instance isn't a Vault node, so there's no local Vault process to talk to). Succeeded on
   the first try: token came back with `["default", "inventory-service"]` policies attached,
   no manual token creation involved. Same rigor as the KV v2 policy: read the secret it's
   scoped to (succeeded), write to that same path (403), read an unrelated path (403).

### Why AWS auth over AppRole here

AppRole's model assumes something trusted already exists to hand out `secret_id`s safely
(response-wrapped, over CI, etc.) — this repo has no such automation by design. AWS auth
sidesteps the problem instead of solving it: the credential is the instance's IAM role,
already scoped by IAM, already rotated by AWS, nothing new to distribute. See
[decision log](../reference/decisions.md) for the full comparison.

## Dynamic secrets (AWS secrets engine)

### Goal

Show the difference that actually matters between Vault and a plain secrets store: dynamic
secrets don't exist until requested, carry their own lease, and Vault can — with caveats, see
below — manage their lifecycle. KV v2 is versioned storage for values that already exist
elsewhere; this generates real, temporary AWS credentials on demand.

### Steps

1. Chose `credential_type = "assumed_role"` over `iam_user` — Vault assumes an existing IAM
   role via STS and hands back the resulting temporary credentials, rather than creating and
   later deleting a real IAM user per lease. No new IAM principals churn through the account;
   the tradeoff is covered below.
2. Added `terraform/vault-config/dynamic-secrets.tf`: a new, narrowly-scoped IAM role
   (`vault-dynamic-demo`, permissions limited to `sts:GetCallerIdentity` only — proving the
   mechanism, not granting real access), trusted to be assumed by the Vault nodes' own IAM
   role (the Vault *server's* identity, since Vault itself is what calls STS on the client's
   behalf here — unrelated to the dedicated client instance from the AWS auth section above);
   an inline policy granting that existing role `sts:AssumeRole` on the new one; the
   `vault_aws_secret_backend` (mounted at `aws/`, no explicit AWS credentials — same
   credential-chain fallback as the auth method's client config); and a
   `vault_aws_secret_backend_role` named `inventory-service`, `role_arns` pointing at the new
   IAM role, `default_sts_ttl = 900`.
3. Extended the `inventory-service` **policy** (the same one used for KV v2 and AWS auth) with
   `read` on `aws/creds/inventory-service` — one app identity, scoped across multiple secrets
   engines by the same policy, rather than a new policy per engine.
4. **Verified with real AWS credentials, not just a successful `vault read`** — from the same
   demo client instance used for the AWS auth test: logged in via AWS auth, read
   `aws/creds/inventory-service` (got back an access key, secret key, session token, and a
   lease), then actually used those credentials against AWS STS `get-caller-identity`.
   Confirmed the resulting identity was the *assumed* role
   (`assumed-role/vault-dynamic-demo/...`), not the client instance's own role — proof the
   assumption really happened, not just that Vault returned *something*.

### A verified gotcha: `assumed_role` revocation is soft

Tested explicitly rather than assumed: revoked the lease with the root token
(`vault lease revoke`, confirmed `Success!`), then retried the *same* already-issued
credentials against STS again. They still worked — full `get-caller-identity` success, same
identity, no error. Root cause is on the AWS side, not Vault's: STS has no general-purpose
API to invalidate an already-issued temporary credential before its own expiry (AWS's own
documented workaround is a deny policy keyed on `aws:SessionIssueTime`, which Vault doesn't
apply automatically). So `vault lease revoke` on an `assumed_role` (or `federation_token`)
lease only stops Vault from tracking/renewing it — the credentials themselves stay valid
until their TTL naturally expires (900s here). `iam_user` credentials don't have this gap —
deleting the dynamically-created IAM user immediately kills its access key. This
is the real cost of choosing `assumed_role`: faster to set up, no IAM user churn, but
"revoke" means "stop renewing," not "revoke," for the credential's remaining TTL.

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
- A non-Vault-server instance has no local Vault process to talk to — point `VAULT_ADDR` at
  the cluster's real address (`vault.sandbox.internal:8200`), not `127.0.0.1`, and supply its
  own copy of the CA cert (it won't have `/etc/vault.d/tls/ca.pem`, that only exists on the
  Vault nodes themselves).
- `vault lease revoke` on an `assumed_role`/`federation_token` AWS secrets engine lease
  doesn't invalidate the credentials themselves — AWS STS has no general revocation API, so
  only `iam_user` leases support true immediate revocation (that path deletes a real IAM
  user/key). Verified directly by revoking a lease and successfully reusing the same
  credentials afterward, rather than trusting the docs' phrasing at a glance.

## References

- [KV Secrets Engine v2 (Vault docs)](https://developer.hashicorp.com/vault/docs/secrets/kv/kv-v2)
- [Policies (Vault docs)](https://developer.hashicorp.com/vault/docs/concepts/policies)
- [AWS Auth Method (Vault docs)](https://developer.hashicorp.com/vault/docs/auth/aws)
- [AWS Secrets Engine (Vault docs)](https://developer.hashicorp.com/vault/docs/secrets/aws)
- [Patterns: multi-team static secrets](../reference/patterns.md)
