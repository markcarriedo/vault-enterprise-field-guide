# Architecture

!!! note "Not started yet"
    Diagram and component breakdown go here once the topology is decided (single node vs.
    HA cluster, storage backend, load balancer, KMS auto-unseal, network layout).

```mermaid
flowchart LR
    Client -->|HTTPS| LB[Load Balancer]
    LB --> V1[Vault Node 1]
    LB --> V2[Vault Node 2]
    LB --> V3[Vault Node 3]
    V1 <--> Storage[(Storage Backend)]
    V2 <--> Storage
    V3 <--> Storage
    V1 -.-> KMS[AWS KMS - Auto Unseal]
    V2 -.-> KMS
    V3 -.-> KMS
```

*Placeholder diagram — update once the real topology is confirmed.*
