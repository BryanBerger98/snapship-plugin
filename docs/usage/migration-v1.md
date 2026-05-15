# Migration v0.6 → v1.0

Snap v1.0.0 is a **breaking refactor** centered on "remote platforms =
sources of truth". Local serves only to pre-generate, validate, and stage
before pushing. Nothing is duplicated locally by default (except
`manifests/` and `tickets/`, which are essential references).

> **TL;DR**: run `/snap:upgrade` in each project that used snap v0.6.x. The
> skill detects the version, backs up `.snap/` (or `.claude/product/`) to
> `.snap.bak-v0-{timestamp}/`, applies the migrations, and validates.

## Recommended procedure

```text
/snap:upgrade --dry-run       # 1. preview the plan
/snap:upgrade                 # 2. apply (auto backup)
/snap:fetch --all             # 3. re-sync from remote to absorb drift
```

Failure during `step-03-apply` → automatic rollback from the backup.
Failure in `step-04-validate` → workspace migrated but schemas must be
fixed manually (no rollback at this stage).

## Breaking changes — paths

| v0.6                                                 | v1.0                                                |
| ---------------------------------------------------- | --------------------------------------------------- |
| `.snap/features/{slug}/meta.json`                    | `.snap/manifests/{feature_id}.manifest.json`        |
| `.snap/features/{slug}/tickets.json`                 | `.snap/tickets/{feature_id}.json`                   |
| `.snap/features/{slug}/wireframes/`                  | `.snap/wireframes/{feature_id}/`                    |
| `.snap/features/{slug}/design/`                      | `.snap/designs/{feature_id}/`                       |
| `.snap/features/{slug}/prd-feature.md`               | `.snap/PRDs/{feature_id}.md`                        |
| `.snap/features/{slug}/progress.md`                  | `.snap/progress.json` (centralized, gitignored)     |
| `.snap/domains.json`                                 | `.snap/manifests/_taxonomy.json`                    |
| `.snap/index.md`                                     | _removed_ — state read from `manifests/` + `_taxonomy.json` |
| `.claude/product/` (legacy)                          | `.snap/`                                            |
| `artysan.config.json`                                | `snapship.config.json`                              |

## Breaking changes — `_shared/` helpers

| v0.6                                              | v1.0                                              |
| ------------------------------------------------- | ------------------------------------------------- |
| `update-progress.sh` + `resume-state.sh`          | `progress.sh` (sub-commands `start`/`step`/`finish`/`resume`) |
| `setup-product-dir.sh`                            | `setup-snap-dir.sh`                               |
| `domains-state.sh`                                | `taxonomy-state.sh`                               |
| `telemetry.sh emit` / `append`                    | `telemetry.sh log`                                |
| `load-config.sh` (cache `.config-resolved.json`)  | `load-config.sh` returns on stdout, no cache      |
| `update-index.sh`                                 | _removed_ — manifests + taxonomy replace it       |
| —                                                 | `sync-push.sh` (new, write-through outbox)        |
| —                                                 | `sync-fetch.sh` (new, refs replay)                |

## Breaking changes — skills

- **`/snap:develop`**: `daemon` mode removed. Session-only loop.
  `develop.loop.daemon.*` removed from the config schema.
- **`/snap:design`**: `ds-extract` / `ds-init` / `ds-update` modes removed
  (already removed in v0.6.x under `refactor/design-mockup-only`). The
  design system is managed outside the plugin.
- **`/snap:upgrade`** (new): migration framework, idempotent.
- **`/snap:fetch`** (new): re-sync local caches from the platforms (replay
  manifest `refs`).

## Breaking changes — config (`snapship.config.json`)

| v0.6 key                       | v1.0                                                  |
| ------------------------------ | ----------------------------------------------------- |
| `develop.loop.daemon`          | removed — `additionalProperties:false` rejects it     |
| `design.extract.*`             | removed                                               |
| `design.figma.bridge_kb_path`  | removed                                               |
| `design.figma.bridge_transport`| removed                                               |
| —                              | `templates.use_repo_native` (bool, default `true`)    |
| —                              | `version` bumped `0.6.x` → `1.0`                      |

Schemas use `additionalProperties:false` ⇒ an orphan key = validation
error. `/snap:upgrade` cleans up automatically.

## State machine — manifest

v1.0 introduces an explicit state machine on each manifest
(`.snap/manifests/{feature_id}.manifest.json`):

```
defined → ticketed → wireframed → designed → developed → qa-validated → shipped
```

Each terminal skill writes the transition. `/snap:fetch` can detect drift
between local state and remote state (PR merged outside snap, ticket closed
manually) — it then proposes a reconciliation.

## `.gitignore`

v1.0 whitelists `manifests/` and `tickets/`, ignores everything else:

```gitignore
.env.snapship
.env.snapship.*
.snap/*
!.snap/manifests/
!.snap/tickets/
.snap.bak-*
.config-resolved.json
.claude/product/
```

→ nothing for the team to regenerate: `tickets/` + `manifests/` are enough
for a new member to `/snap:fetch --all` and rebuild the context.

## Post-upgrade verification

```bash
jq '.version' snapship.config.json                # → "1.0"
jq '.schema_version' .snap/manifests/_taxonomy.json  # → "1.0"
ls .snap/manifests/                               # *.manifest.json + _taxonomy.json
ls .snap/tickets/                                 # *.json
test -f .snap/progress.json && echo OK            # central, no more per-feature
test ! -d .claude/product/ && echo OK             # legacy purged
```

If a step returns `KO`, run `/snap:upgrade` again (idempotent) or restore
from `.snap.bak-v0-{timestamp}/`.

## More details

- [CHANGELOG.md](../CHANGELOG.md) — v1.0.0 entry (all breakages)
- [structure.md](../contributing/structure.md) — new `.snap/` layout
- [scripts.md](../contributing/scripts.md) — refactored helper contracts
