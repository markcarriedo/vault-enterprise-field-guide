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

## Gotchas

- `operator init` does not enable any secrets engines — `secret/` (or any other KV mount)
  has to be created explicitly. Only `-dev` mode auto-mounts one.
- Testing a policy by reading it isn't enough — a policy that *parses* isn't the same as a
  policy that *enforces* correctly. Always test with an actual token scoped to it, not the
  root token, before trusting it.

## References

- [KV Secrets Engine v2 (Vault docs)](https://developer.hashicorp.com/vault/docs/secrets/kv/kv-v2)
- [Policies (Vault docs)](https://developer.hashicorp.com/vault/docs/concepts/policies)
- [Patterns: multi-team static secrets](../reference/patterns.md)
