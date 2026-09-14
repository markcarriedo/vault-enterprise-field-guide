# Test Transit encryption (encryption as a service)

Like [dynamic AWS secrets](dynamic-aws-secrets.md), this runs **from the dedicated demo client
instance**, not a Vault node — proving the app identity can actually use the key, not just that
`vault write` succeeds as root.

```bash
# 1. Fresh AWS credentials, then a real shell on the demo client instance
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=inventory-service-instance" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].InstanceId" --output text)

aws ssm start-session --target "$INSTANCE_ID"
```

```bash
# 2. On the instance: fetch the CA cert and point at the cluster's real
#    in-VPC address - same setup as the dynamic-secrets runbook
aws secretsmanager get-secret-value \
  --secret-id vault-enterprise/tls-ca-bundle \
  --query SecretString --output text | base64 -d > /tmp/vault-ca.pem

export VAULT_ADDR=https://vault.sandbox.internal:8200
export VAULT_CACERT=/tmp/vault-ca.pem
```

```bash
# 3. Log in via AWS auth, then encrypt and decrypt real data
export VAULT_TOKEN=$(vault login -method=aws role=inventory-service -format=json | \
  python3 -c "import json,sys; print(json.load(sys.stdin)['auth']['client_token'])")

CIPHERTEXT=$(vault write -field=ciphertext transit/encrypt/inventory-service \
  plaintext=$(echo -n "order-42:card-4111-1111-1111-1111" | base64))
echo "$CIPHERTEXT"
# vault:v1:... - the v1 is the key version, not a secret itself

vault write -field=plaintext transit/decrypt/inventory-service ciphertext="$CIPHERTEXT" | base64 -d
# should print the original plaintext back exactly
```

```bash
# 4. Prove the app can use the key without ever seeing it - both of these
#    must come back 403 permission denied
vault read transit/keys/inventory-service
vault read transit/export/encryption-key/inventory-service
```

```bash
# 5. (Operator-only, from your laptop with the root token) rotate the key
#    and confirm old ciphertexts still decrypt - the actual value of a
#    versioned key, not just "encryption happened"
vault write -f transit/keys/inventory-service/rotate
vault write -field=plaintext transit/decrypt/inventory-service ciphertext="$CIPHERTEXT" | base64 -d
# still decrypts under v1, even though the key is now on v2

vault write -field=ciphertext transit/encrypt/inventory-service plaintext=$(echo -n "new" | base64)
# now returns vault:v2:... - new encryptions use the latest version automatically
```

Verified end-to-end: the app identity encrypted and decrypted real data, got a clean 403 on
both key-read and key-export, and — after an operator rotated the key — a ciphertext produced
before rotation still decrypted correctly while new encryptions moved to the new version
automatically.

## Gotchas

- The first request after a fresh AWS-auth login sometimes returns `412: required index state
  not present` when talking to the cluster through the internal load balancer. This is Vault
  Enterprise's read-after-write consistency check: the login (a write) and the next request can
  land on different Raft nodes behind the LB, and the second node hasn't caught up yet. It's not
  a real error — retry the request (it resolved within 1-2 attempts every time in testing) or
  point directly at the active node instead of the LB address if it happens repeatedly.
- `vault read transit/keys/<name>` returns key **metadata** (versions, timestamps, capabilities)
  even for someone who has `read` on that path — it never returns raw key bytes on its own.
  Actual key material only comes back from `transit/export/<type>/<name>`, and only if the key
  was created with `exportable = true` (a one-way flag, cannot be unset). This build's key
  never sets it, and the app policy has no access to either path regardless.
- `vault:v1:...` / `vault:v2:...` in a ciphertext identifies which key *version* encrypted it —
  it's metadata for decryption, not sensitive on its own, and it's exactly how a versioned key
  supports rotation without breaking old ciphertexts.

## References

- [Transit Secrets Engine (Vault docs)](https://developer.hashicorp.com/vault/docs/secrets/transit)
- [Transit Secrets Engine HTTP API (Vault docs)](https://developer.hashicorp.com/vault/api-docs/secret/transit)
