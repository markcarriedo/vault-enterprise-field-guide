# Runbooks

Day-to-day operational procedures for the running cluster — connecting to it, checking on it,
credential rotation, onboarding a new team/app. Unlike the [Guide](../guide/index.md) (a
one-time build sequence), these are standalone runbooks that get used repeatedly, added to as
new operational needs come up — not a one-time milestone.

- [Connect to the cluster manually](connect-manually.md) — ad-hoc testing/troubleshooting, no
  bastion host, straight to a node over SSM.
- [Test dynamic AWS secrets](dynamic-aws-secrets.md) — AWS auth login plus the AWS secrets
  engine, from the dedicated demo client instance.
- [Verify audit logging](audit-logging.md) — confirm audit events actually land in CloudWatch,
  with sensitive fields hashed.
- [Backup and restore a Raft snapshot](raft-snapshot-backup-restore.md) — the disaster-recovery
  mechanism for Integrated Storage, verified with a safe round-trip test.
- [Regenerate the root token](root-token-regeneration.md) — the break-glass procedure using a
  quorum of recovery keys, no old token required.
- [Recover from a lost Vault node](node-replacement.md) — what actually happens when a Raft
  node dies and the ASG replaces it, verified against a real termination.
- [Test Transit encryption](transit-encryption.md) — encrypt/decrypt real data as the app
  identity, confirm it can never read or export the key, verify rotation.
- [Test PKI certificate issuance](pki-certificates.md) — issue and chain-verify a real
  certificate as the app identity, confirm it can't revoke certs or manage the CA.
