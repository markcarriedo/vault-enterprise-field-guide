# AWS Infrastructure

## Goal

Provision everything the HVD module expects to already exist (see
[Planning & Prerequisites](01-planning.md)) — VPC, KMS key, TLS material, and the license —
before touching the module itself. Two small Terraform configs, applied in order:

- **`terraform/bootstrap/`** — the S3 bucket everything else uses for remote state
- **`terraform/prerequisites/`** — the VPC, KMS key, private DNS zone, TLS cert, and the four
  Secrets Manager entries

## Steps

### 1. State bucket

`terraform/bootstrap/` creates a single S3 bucket (versioned, KMS-encrypted, public access
blocked, insecure-transport denied) and uses **local** state itself — the standard
chicken-and-egg exception for bootstrapping a backend. Applied once; rarely touched again.

### 2. VPC

Built with the community `terraform-aws-modules/vpc/aws` module rather than hand-written
resources: 3 AZs, 3 public subnets (exist only to host the NAT Gateway — nothing user-facing
lives there) and 3 private subnets (Vault nodes **and** the internal-scheme load balancer both
live here). Single NAT Gateway, not one per AZ — cheaper, less resilient, a deliberate
sandbox-cost tradeoff (`single_nat_gateway` variable if you want to change it).

### 3. KMS key

One symmetric key, rotation enabled, dedicated to Vault auto-unseal — nothing else uses it.

### 4. TLS: private Route53 zone + self-signed CA

`vault.sandbox.internal`, resolved by a Route53 **private** hosted zone associated with the
VPC — no real domain needed, since private zones don't validate ownership. Cert is a
self-signed CA + leaf, generated declaratively via the `hashicorp/tls` provider (not a
separate `openssl` script), so key material lives in Terraform state alongside everything
else rather than as loose files on disk. See the
[decision log](../reference/decisions.md) for why we dropped a real domain entirely and for
the enterprise-vs-sandbox tradeoff on the CA choice.

### 5. Secrets Manager

Four secrets: the license (read from a local `.hclic` file, its path is a variable, the file
itself is never committed) and the three TLS pieces (cert, key, CA bundle — each
base64-encoded per the module's requirement).

## Gotchas

- The account's **default VPC** isn't usable as-is — public subnets only, no NAT gateways, no
  private subnets. Confirmed by survey before building anything (see decision log).
- A NAT Gateway must live in a **public** subnet even though it only serves private-subnet
  traffic — easy to get backwards when designing the subnet layout by hand.
- Route53 **private** hosted zones don't validate domain ownership at all (only public zones
  and public-CA cert issuance do) — this is what let us drop the real domain we'd originally
  planned to use and use a made-up internal name instead.

## References

- [terraform-aws-modules/vpc/aws (Terraform Registry)](https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/latest)
- [hashicorp/tls provider (Terraform Registry)](https://registry.terraform.io/providers/hashicorp/tls/latest/docs)
- [Decision log](../reference/decisions.md) — sandbox account/region, no local AWS profile,
  TLS/private-zone approach
