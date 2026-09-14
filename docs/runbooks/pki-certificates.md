# Test PKI certificate issuance

Like [Transit](transit-encryption.md), this runs **from the dedicated demo client instance**,
proving the app identity can request a real, chain-verifiable certificate — and nothing more.

```bash
# 1. Fresh AWS credentials, then a real shell on the demo client instance
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=inventory-service-instance" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].InstanceId" --output text)

aws ssm start-session --target "$INSTANCE_ID"
```

```bash
# 2. On the instance: fetch the CA cert and point at the cluster's real
#    in-VPC address - same setup as every other app-identity runbook
aws secretsmanager get-secret-value \
  --secret-id vault-enterprise/tls-ca-bundle \
  --query SecretString --output text | base64 -d > /tmp/vault-ca.pem

export VAULT_ADDR=https://vault.sandbox.internal:8200
export VAULT_CACERT=/tmp/vault-ca.pem
```

```bash
# 3. Log in via AWS auth, then request a real certificate from this app's
#    own PKI role
export VAULT_TOKEN=$(vault login -method=aws role=inventory-service -format=json | \
  python3 -c "import json,sys; print(json.load(sys.stdin)['auth']['client_token'])")

vault write -format=json pki_int/issue/inventory-service \
  common_name=inventory-service.svc.internal > /tmp/cert-response.json

python3 -c "
import json
d = json.load(open('/tmp/cert-response.json'))['data']
open('/tmp/leaf.pem', 'w').write(d['certificate'])
open('/tmp/chain.pem', 'w').write(d['issuing_ca'] + '\n')
print('serial:', d['serial_number'])
"
```

```bash
# 4. Verify the full chain against the actual PKI root - not the cluster's
#    own TLS CA, a completely different CA (see the gotcha below)
vault read -field=certificate pki/cert/ca > /tmp/pki-root-ca.pem
openssl verify -CAfile /tmp/pki-root-ca.pem -untrusted /tmp/chain.pem /tmp/leaf.pem
# /tmp/leaf.pem: OK

openssl x509 -in /tmp/leaf.pem -noout -subject -issuer -enddate
```

```bash
# 5. Prove the app can request certs but can't manage the CA - all three
#    of these must come back 403
vault write pki_int/revoke serial_number="<serial from step 3>"
vault read pki_int/config/ca
vault list pki_int/certs
```

```bash
# 6. (Operator-only, from your laptop with the root token) revoke the cert
#    and confirm it actually lands on the CRL
vault write pki_int/revoke serial_number="<serial from step 3>"

curl -s --cacert /tmp/vault-ca.pem https://vault.sandbox.internal:8200/v1/pki_int/crl/pem \
  | openssl crl -noout -text | grep -A2 "Serial Number"
```

Verified end-to-end: the app identity requested a cert, the full chain (leaf → intermediate →
root) verified with `openssl` against the real PKI root CA, and revoke/CA-config/cert-listing
all correctly came back 403 for the app. An operator's revocation showed up on the CRL with the
correct timestamp within seconds.

## Gotchas

- This build has **two separate, unrelated CAs** — the cluster's own TLS CA (`vault-enterprise/tls-ca-bundle`,
  used to trust Vault's own HTTPS listener) and the new PKI-issued root CA (`pki/cert/ca`, used
  to trust certificates Vault *issues*). Verifying an issued certificate's chain against the
  wrong one fails with "unable to get local issuer certificate" — a real mistake made while
  building this runbook, not a hypothetical one.
- `vault write pki_int/revoke` and `vault read pki_int/config/ca` are correctly denied for the
  app identity (403) — the app's policy only grants `pki_int/issue/inventory-service`. An app
  that could revoke its own certs, or read the CA's own config, defeats the point of a
  centrally-managed CA.
- A revoked certificate's serial number appears on the CRL (`pki_int/crl/pem`) almost
  immediately — worth checking directly rather than trusting `vault write pki_int/revoke`'s
  success message alone, same rule as everywhere else in this build.

## References

- [PKI Secrets Engine (Vault docs)](https://developer.hashicorp.com/vault/docs/secrets/pki)
- [PKI Secrets Engine HTTP API (Vault docs)](https://developer.hashicorp.com/vault/api-docs/secret/pki)
- [PKI considerations (Vault docs)](https://developer.hashicorp.com/vault/docs/secrets/pki/considerations)
