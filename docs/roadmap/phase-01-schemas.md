# Phase 1 — Schemas & validation

**Objectif:** schemas JSON utilisés par toute config + meta + tickets.

- [x] `_shared/schemas/config.schema.json` — couvre toutes sections `snapship.config.json` (repository, tickets+jira nested, documentation, wireframes, testing, naming, ai, develop, qa, lifecycle_scripts, defaults)
- [x] `_shared/schemas/meta.schema.json` — feature `meta.json` (feature_id, affine_page_id, branch_name, etc.)
- [x] `_shared/schemas/tickets.schema.json` — cache `tickets.json`
- [x] Tests fixtures valides + invalides par schema
- [x] CI exécute validation sur fixtures

**Sortie:** schemas testés, base solide load-config.
