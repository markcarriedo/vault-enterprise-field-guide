# Patterns

General techniques worth explaining once, rather than re-deriving every time a guide chapter
touches them. Unlike the [guide](../guide/index.md), these aren't "what we did" — they're "the
technique, and when it applies," which may go beyond what this particular sandbox build
actually needed.

## Multi-team static secrets

Three patterns for separating secrets between teams or workloads, roughly in order of how
much administrative isolation they provide.

| | 1. Path-namespaced (one mount) | 2. Separate mounts per team | 3. Namespaces (Enterprise) |
|---|---|---|---|
| **What actually separates teams** | Just the ACL policy path (`secret/team-a/*` vs `secret/team-b/*`) | A distinct KV engine instance per team | A distinct policy/auth/engine/audit *root* per team |
| **Mount settings (max versions, TTLs, etc.)** | Shared by everyone — can't differ per team | Independent per team | Independent per team |
| **Can a team self-manage without central admin?** | No | No — central admin still owns and tunes the mount | Yes — that's the entire point of namespaces |
| **Audit trail** | Interleaved, filter by path | Interleaved, filter by mount | Genuinely separable per namespace |
| **License** | OSS or Enterprise | OSS or Enterprise | Enterprise only |
| **Real isolation from another team's mistake** | Weak (one shared mount) | Medium (own mount, still shared policy/auth config space) | Strong (own everything) |
| **Setup effort** | Lowest | Medium | Highest |

The dividing line: patterns 1 and 2 only ever differ in *where the paths live* — both still
require one central team to manage every policy and auth method for everyone. Pattern 3 is
qualitatively different — it delegates actual administration, so a team can create its own
secrets engines and auth methods without needing (or touching) anyone else's configuration.

### When each is worth it

**Pattern 1** — a single team with a handful of related apps under one admin/compliance
boundary already. This is what this field guide's own sandbox uses (`secret/field-guide/*`,
one app).

**Pattern 2** — distinct teams under the *same* legal/regulatory entity that want operational
independence (different secret retention, cleaner blast-radius lines) but don't need to run
their own auth methods. A central Vault team still administers everything.

**Pattern 3 (Namespaces)** — where there's an actual regulatory or organizational reason for
separate administrative control, not just preference:

- **Separate legal entities** — a subsidiary under a different regulator. Auditors often want
  demonstrable separation, not just "we used different paths."
- **Compliance scope isolation** — e.g. PCI-DSS-scoped secrets walled off from general
  corporate IT, with restricted admin access matching the segmentation requirement.
- **Independent security accreditation** — a system with its own security assessment
  (PSPF/ISM-style, or equivalent) often wants its own administrative boundary, especially if
  that division runs its own platform team.
- **Internal Vault-as-a-service** — one shared cluster serving many divisions, each treated
  like a tenant.

In practice, these nest rather than being mutually exclusive at scale: Namespaces mark the
big compliance/legal-entity boundaries, and *within* each namespace, pattern 1 or 2 organizes
the finer team/app structure. A large organization wouldn't run everything on path-naming
discipline alone, but it also wouldn't give every small app team its own namespace — that's
namespace sprawl without a compliance justification behind it.
