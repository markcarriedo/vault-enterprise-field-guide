# Architecture

The real, deployed topology — see [Planning & Prerequisites](../guide/01-planning.md) and
[Installing Vault Enterprise](../guide/03-installation.md) for how each piece got built.

```mermaid
flowchart TB
    You["Your laptop"]

    subgraph AWS["HashiCorp sandbox account, ap-southeast-2"]
        subgraph VPC["VPC 10.0.0.0/16"]
            NAT["NAT Gateway\n(public subnets x3 - nothing else lives here)"]
            LB["Internal NLB\n(ingress restricted to VPC CIDR)"]
            V1["Vault node 1\nleader"]
            V2["Vault node 2\nfollower"]
            V3["Vault node 3\nfollower"]
            App["inventory-service\ndemo client - SSM access only"]
        end
        KMS["AWS KMS\nauto-unseal key"]
        SM["Secrets Manager\nlicense, TLS cert/key/CA, init output"]
        R53["Route53 private zone\nvault.sandbox.internal"]
        CW["CloudWatch Logs\naudit log shipping"]
        S3["S3\nRaft snapshots"]
    end

    You -->|"SSM port-forward\n(no bastion)"| V1
    LB --> V1
    LB --> V2
    LB --> V3
    App -->|"AWS auth login,\nthen Vault requests"| LB
    V1 <-->|Raft| V2
    V2 <-->|Raft| V3
    V1 <-->|Raft| V3
    V1 -.->|unseal| KMS
    V2 -.->|unseal| KMS
    V3 -.->|unseal| KMS
    V1 -.->|reads at boot| SM
    R53 -.->|resolves to| LB
    V1 -.->|outbound only, via NAT| NAT
    V1 -.->|"CloudWatch Agent\n(SSM-managed)"| CW
    V2 -.->|"CloudWatch Agent\n(SSM-managed)"| CW
    V3 -.->|"CloudWatch Agent\n(SSM-managed)"| CW
    You -.->|"manual save/upload,\ndownload/restore"| S3
```

## Components

- **VPC** — 3 AZs, public subnets exist only to host the NAT Gateway; private subnets hold
  both the Vault nodes and the internal load balancer.
- **Load balancer** — internal-scheme NLB (module default), never internet-facing. Ingress
  restricted to the VPC's own CIDR — nothing outside can reach it regardless of DNS.
- **Vault nodes** — 3x EC2 in an Auto Scaling Group, Integrated Storage (Raft) for HA, no
  separate storage backend (no Consul).
- **Demo client (`inventory-service`)** — a dedicated, minimal EC2 instance with no AWS
  permissions beyond SSM access, existing purely to *be* a distinct IAM identity for the AWS
  auth method — deliberately not one of the Vault nodes' own roles.
- **Auto-unseal** — AWS KMS, dedicated key. No Shamir unseal keys; `operator init` instead
  produces recovery key shares (for operations like root-token regeneration, not routine
  unsealing).
- **TLS** — self-signed CA + leaf cert for `vault.sandbox.internal`, generated declaratively
  via the `tls` Terraform provider.
- **DNS** — Route53 **private** hosted zone, associated with the VPC. Doesn't validate
  ownership (only public zones do), which is what let this avoid depending on a real domain.
- **Audit logging** — a `file` audit device shipped to CloudWatch Logs by the AWS CloudWatch
  Agent, installed and configured via SSM State Manager rather than the Vault nodes' own
  launch template.
- **Raft snapshots** — a dedicated, versioned, KMS-encrypted S3 bucket, populated by an
  operator manually running `vault operator raft snapshot save` + `aws s3 cp` (not Vault
  Enterprise's own automated snapshot agent — see the [decision log](decisions.md)).
- **Access** — SSM port-forwarding straight to a node's own port, no bastion host, no public
  ingress path at all.

## Not yet built

Transit (encryption as a service), PKI, and Namespaces — see the [guide](../guide/index.md)
for what's next. Static secrets (KV v2), a least-privilege policy, an AWS auth method,
dynamic AWS credentials via the AWS secrets engine, audit logging to CloudWatch, and Raft
snapshot backup/restore are already live, all Terraform-managed — see
[Configuration](../guide/04-configuration.md).
