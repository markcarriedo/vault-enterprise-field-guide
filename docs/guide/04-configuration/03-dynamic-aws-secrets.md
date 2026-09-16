# Dynamic secrets (AWS secrets engine)

## Goal

Show the difference that actually matters between Vault and a plain secrets store: dynamic
secrets don't exist until requested, carry their own lease, and Vault can — with caveats, see
below — manage their lifecycle. [KV v2](01-static-secrets.md) is versioned storage for values
that already exist elsewhere; this generates real, temporary AWS credentials on demand.

## Steps

1. Chose `credential_type = "assumed_role"` over `iam_user` — Vault assumes an existing IAM role
   via STS and hands back the resulting temporary credentials, rather than creating and later
   deleting a real IAM user per lease. No new IAM principals churn through the account; the
   tradeoff is covered below.
2. Added `terraform/vault-config/dynamic-secrets.tf`: a new, narrowly-scoped IAM role
   (`vault-dynamic-demo`, permissions limited to `sts:GetCallerIdentity` only — proving the
   mechanism, not granting real access), trusted to be assumed by the Vault nodes' own IAM role
   (the Vault *server's* identity, since Vault itself is what calls STS on the client's behalf
   here — unrelated to the dedicated client instance from [AWS auth](02-aws-auth.md)); an
   inline policy granting that existing role `sts:AssumeRole` on the new one; the
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

## A verified gotcha: `assumed_role` revocation is soft

Tested explicitly rather than assumed: revoked the lease with the root token (`vault lease
revoke`, confirmed `Success!`), then retried the *same* already-issued credentials against STS
again. They still worked — full `get-caller-identity` success, same identity, no error. Root
cause is on the AWS side, not Vault's: STS has no general-purpose API to invalidate an
already-issued temporary credential before its own expiry (AWS's own documented workaround is a
deny policy keyed on `aws:SessionIssueTime`, which Vault doesn't apply automatically). So `vault
lease revoke` on an `assumed_role` (or `federation_token`) lease only stops Vault from
tracking/renewing it — the credentials themselves stay valid until their TTL naturally expires
(900s here). `iam_user` credentials don't have this gap — deleting the dynamically-created IAM
user immediately kills its access key. This is the real cost of choosing `assumed_role`: faster
to set up, no IAM user churn, but "revoke" means "stop renewing," not "revoke," for the
credential's remaining TTL.

## Gotchas

- `vault lease revoke` on an `assumed_role`/`federation_token` AWS secrets engine lease doesn't
  invalidate the credentials themselves — AWS STS has no general revocation API, so only
  `iam_user` leases support true immediate revocation (that path deletes a real IAM user/key).
  Verified directly by revoking a lease and successfully reusing the same credentials
  afterward, rather than trusting the docs' phrasing at a glance.

## References

- [AWS Secrets Engine (Vault docs)](https://developer.hashicorp.com/vault/docs/secrets/aws)
- [Test dynamic AWS secrets (runbook)](../../runbooks/dynamic-aws-secrets.md)
