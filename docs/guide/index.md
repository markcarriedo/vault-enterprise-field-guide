# Guide Overview

The reference path through this build, in order. Each section is filled in once we've
actually done that part and validated it — see the [journal](../journal/index.md) for the
in-progress notes and discoveries behind each one.

1. [Planning & Prerequisites](01-planning.md)
2. [AWS Infrastructure](02-aws-infrastructure.md)
3. [Installing Vault Enterprise](03-installation.md)
4. [Configuration](04-configuration.md)
5. [Troubleshooting](05-troubleshooting.md)

Storage backend, auto-unseal, TLS, and clustering/HA don't get their own steps — the HVD
module bundles all of them into step 3, and they're covered there and in
[Architecture](../reference/architecture.md) rather than as separate build steps.

Day-to-day operational procedures (connecting to the cluster, testing dynamic secrets, backup/
restore, credential rotation) aren't part of this one-time build sequence — see
[Runbooks](../runbooks/index.md).
