# Vault Enterprise on AWS EC2 — Field Guide

A working field guide for installing and configuring [HashiCorp Vault Enterprise](https://www.hashicorp.com/products/vault)
on AWS EC2 — written as we go, gotchas and dead ends included, not cleaned up after the fact.

<div class="grid cards" markdown>

-   __Guide__

    ---

    The numbered how-to: planning, AWS infra, installation, configuration, storage,
    auto-unseal, TLS, clustering/HA, troubleshooting.

    [:octicons-arrow-right-24: Start reading](guide/index.md)

-   __Runbooks__

    ---

    Day-to-day operational procedures — connecting to the cluster, testing dynamic secrets,
    backup/restore, credential rotation. Open-ended, growing as new needs come up.

    [:octicons-arrow-right-24: Browse runbooks](runbooks/index.md)

-   __Reference__

    ---

    Architecture diagram, an ADR-style decision log, and a glossary — the "why," not just the
    "how."

    [:octicons-arrow-right-24: Browse reference](reference/architecture.md)

-   __Journal__

    ---

    Dated field notes, in the order things happened — the story: what we tried, what broke,
    what we decided, and why.

    [:octicons-arrow-right-24: Read the journal](journal/index.md)

</div>

## Status

- [x] Prerequisites — VPC, KMS auto-unseal key, TLS (private Route53 zone + self-signed CA),
      license — all in AWS Secrets Manager / Terraform-managed
- [x] Vault cluster deployed — 3 nodes healthy behind an internal load balancer, HA via
      Integrated Storage (Raft), running `2.1.0+ent`
- [x] Initialized & unsealed — auto-unseal via KMS, 3/3 nodes confirmed as Raft peers (1
      leader, 2 followers), root token + recovery keys secured in Secrets Manager
- [ ] Configuration — static secrets (KV v2), a verified least-privilege policy, an AWS auth
      method so real workloads stop using the root token, dynamic AWS credentials via the
      AWS secrets engine, and audit logging to CloudWatch; Transit and PKI still to come
- [ ] [Runbooks](runbooks/index.md) — five so far (connecting to the cluster manually, testing
      dynamic secrets, verifying audit logging, Raft snapshot backup/restore, root token
      regeneration); an open-ended category, not a one-time milestone

See the [journal](journal/index.md) for the day-by-day story, or the
[decision log](reference/decisions.md) for why things were built the way they were.
