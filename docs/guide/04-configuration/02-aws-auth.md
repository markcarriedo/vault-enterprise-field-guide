# AWS auth method

## Goal

Stop using the root token for routine work. The `inventory-service` policy already existed
(see [Static secrets](01-static-secrets.md)); what was missing was a way for something *other
than a human with the root token* to get a token scoped to it.

## Steps

1. Considered AppRole first, the more commonly-documented option — rejected for this build
   specifically: AppRole's `secret_id` needs a trusted distributor (CI/CD, an orchestrator) to
   vend it safely, and this repo deliberately has none (`terraform` runs locally only, no
   pipeline — see decision log). Response-wrapping the `secret_id` by hand defeats the point of
   automating auth in the first place.
2. Used the **AWS auth method** instead: an EC2 instance authenticates using its own IAM role
   identity (a signed STS `GetCallerIdentity` request) — no `secret_id`, nothing to vend or
   leak, since the credential *is* the instance's already-existing IAM role.
3. Added a dedicated, minimal EC2 instance (`terraform/vault-config/demo-client.tf`) as the
   client proving the pattern — not one of the Vault nodes' own roles. A real app shouldn't
   authenticate to Vault as the Vault server itself, so this instance exists purely to *be* a
   distinct IAM identity: no AWS permissions beyond SSM access to reach it for testing.
4. Added `vault_auth_backend`, `vault_aws_auth_backend_client`, and `vault_aws_auth_backend_role`
   to `terraform/vault-config/auth.tf` — bound to that dedicated instance's IAM role (looked up
   by name via a Terraform data source, not by ARN, so the AWS account ID never appears
   literally in a committed file), `token_policies = ["inventory-service"]`, `auth_type =
   "iam"`.
5. **Verified end-to-end from the instance itself** — IAM-based login only works when the
   *caller* signs its own request, so this couldn't be tested from a laptop; had to SSM onto
   the demo client instance and run `vault login -method=aws role=inventory-service` there
   (pointed at the cluster's real in-VPC address, `vault.sandbox.internal:8200` — this instance
   isn't a Vault node, so there's no local Vault process to talk to). Succeeded on the first
   try: token came back with `["default", "inventory-service"]` policies attached, no manual
   token creation involved. Same rigor as the KV v2 policy: read the secret it's scoped to
   (succeeded), write to that same path (403), read an unrelated path (403).

## Why AWS auth over AppRole here

AppRole's model assumes something trusted already exists to hand out `secret_id`s safely
(response-wrapped, over CI, etc.) — this repo has no such automation by design. AWS auth
sidesteps the problem instead of solving it: the credential is the instance's IAM role, already
scoped by IAM, already rotated by AWS, nothing new to distribute. See
[decision log](../../reference/decisions.md) for the full comparison.

## Gotchas

- AWS IAM-type auth can't be tested from a machine other than the one authenticating — the
  login request has to be signed by the caller's own credentials. Testing from a laptop with
  different AWS credentials just proves the *wrong* identity can't log in, not that the right
  one can.
- A non-Vault-server instance has no local Vault process to talk to — point `VAULT_ADDR` at the
  cluster's real address (`vault.sandbox.internal:8200`), not `127.0.0.1`, and supply its own
  copy of the CA cert (it won't have `/etc/vault.d/tls/ca.pem`, that only exists on the Vault
  nodes themselves). Every later feature verified from this same demo client instance hits the
  same setup.

## References

- [AWS Auth Method (Vault docs)](https://developer.hashicorp.com/vault/docs/auth/aws)
- [Decision log](../../reference/decisions.md)
