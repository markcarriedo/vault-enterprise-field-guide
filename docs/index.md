# Vault Enterprise on AWS EC2 — Field Guide

A working field guide for installing and configuring [HashiCorp Vault Enterprise](https://www.hashicorp.com/products/vault)
on AWS EC2 — written as we go, gotchas and dead ends included, not cleaned up after the fact.

<div class="grid cards" markdown>

-   __Guide__

    ---

    The numbered how-to: planning, AWS infra, installation, configuration, storage,
    auto-unseal, TLS, clustering/HA, operations, troubleshooting.

    [:octicons-arrow-right-24: Start reading](guide/index.md)

-   __Reference__

    ---

    Architecture diagram, an ADR-style decision log, and a glossary — the "why," not just the
    "how."

    [:octicons-arrow-right-24: Browse reference](reference/architecture.md)

-   __Changelog__

    ---

    Commit-by-commit history, generated via git-cliff. Lives at the repo root, not part of
    this site.

    [:octicons-arrow-right-24: View on GitHub](https://github.com/markcarriedo/vault-enterprise-field-guide/blob/main/CHANGELOG.md)

</div>

## Status

- [x] Prerequisites — VPC, KMS auto-unseal key, TLS (private Route53 zone + self-signed CA),
      license — all in AWS Secrets Manager / Terraform-managed
- [x] Vault cluster deployed — 3 nodes healthy behind an internal load balancer, HA via
      Integrated Storage (Raft), running `2.1.0+ent`
- [ ] Initialize & unseal
- [ ] Configuration — secrets engines, auth methods, policies
- [ ] Operations runbooks

See the [changelog](https://github.com/markcarriedo/vault-enterprise-field-guide/blob/main/CHANGELOG.md)
for the day-by-day story, or the [decision log](reference/decisions.md) for why things were
built the way they were.
