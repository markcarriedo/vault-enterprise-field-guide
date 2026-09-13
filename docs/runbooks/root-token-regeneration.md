# Regenerate the root token

The break-glass procedure for replacing the root token without needing the old one — uses a
quorum of recovery key shares instead. Needed if the current root token is suspected
compromised, or simply as periodic hygiene since it's the one credential in this build with no
TTL. This cluster's recovery keys are 5 shares, threshold 3.

```bash
# 1. Fresh AWS credentials, tunnel to a Vault node (see "Connect to the cluster
#    manually"), then fetch the current root token + recovery keys from
#    Secrets Manager - both are needed for this procedure
aws secretsmanager get-secret-value \
  --secret-id vault-enterprise/init-output \
  --query SecretString --output text > /tmp/init-output.json
```

```bash
# 2. Start the generation - returns a nonce (to tie key submissions together)
#    and an OTP (used to decode the final token). Vault 2.0 requires an
#    authenticated token for this endpoint (a hardening change - see the
#    gotcha below), so authenticate with the current root token first.
export VAULT_TOKEN=$(python3 -c "import json; print(json.load(open('/tmp/init-output.json'))['root_token'])")

vault operator generate-root -init -format=json > /tmp/genroot-init.json
NONCE=$(python3 -c "import json; print(json.load(open('/tmp/genroot-init.json'))['nonce'])")
OTP=$(python3 -c "import json; print(json.load(open('/tmp/genroot-init.json'))['otp'])")
```

```bash
# 3. Submit recovery key shares one at a time against the nonce, until quorum
#    (3 of 5) is reached - the last submission returns an encoded_token
for KEY in "<recovery-key-1>" "<recovery-key-2>" "<recovery-key-3>"; do
  vault operator generate-root -nonce="$NONCE" -format=json "$KEY"
done
```

```bash
# 4. Decode the final token with the OTP from step 2
vault operator generate-root -decode="<encoded_token from step 3>" -otp="$OTP" -format=json
```

```bash
# 5. Verify the new token BEFORE touching anything else - a broken new token
#    caught here is an inconvenience; caught after revoking the old one is a
#    lockout with no way back except the recovery keys again
NEW_TOKEN="<new token from step 4>"
VAULT_TOKEN="$NEW_TOKEN" vault token lookup   # confirm policies: ["root"]
```

```bash
# 6. Only once verified: write the new token into Secrets Manager (recovery
# keys are unchanged, only root_token is replaced), then revoke the old one
# using its own value - never the new one - with -self
python3 -c "
import json
d = json.load(open('/tmp/init-output.json'))
d['root_token'] = '$NEW_TOKEN'
json.dump(d, open('/tmp/updated-init-output.json', 'w'))
"
aws secretsmanager put-secret-value \
  --secret-id vault-enterprise/init-output \
  --secret-string file:///tmp/updated-init-output.json

vault token revoke -self   # VAULT_TOKEN is still the OLD token in this shell
```

Verified end-to-end on this cluster: the old token failed `vault token lookup` immediately
after revocation (`permission denied` / `invalid token`), while the new token succeeded on
both a token lookup and a real API call (`vault secrets list`).

## Gotchas

- `sys/generate-root/attempt` (and `sys/rekey`, `sys/replication/dr/secondary/generate-operation-token`)
  now require an authenticated Vault token as of Vault 2.0 — previously these were fully
  unauthenticated, with recovery/unseal key fragments alone as the security boundary. The
  change guards against an attacker submitting bogus key fragments to lock out legitimate use.
  A backward-compatible `enable_unauthenticated_access` server config exists but HashiCorp's
  own guidance is to just supply a valid token instead — which this runbook does, using the
  existing root token to authenticate the request that replaces it.
- Verify a newly-generated root token *before* revoking the old one — revoking first and
  discovering the new token is broken means starting the whole recovery-key procedure over
  again with no working root token in between.
- Any local file holding a root token or recovery keys (`/tmp/init-output.json` etc.) is
  throwaway for the duration of this runbook only — delete it immediately after use, same as
  the CA cert.

## References

- [`operator generate-root` command (Vault docs)](https://developer.hashicorp.com/vault/docs/commands/operator/generate-root)
- [`/sys/generate-root` HTTP API (Vault docs)](https://developer.hashicorp.com/vault/api-docs/system/generate-root)
- [Important changes: authentication requirements (Vault docs)](https://developer.hashicorp.com/vault/docs/updates/important-changes)
