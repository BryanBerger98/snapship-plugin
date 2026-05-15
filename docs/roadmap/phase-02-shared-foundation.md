# Phase 2 — Scripts `_shared/` foundation

**Objectif:** scripts socle utilisés par tous skills.

Ordre dépendances:

1. [x] `load-config.sh` (lit config + defaults + valide schema)
2. [x] `setup-product-dir.sh` (init `.snap/`)
3. [x] `update-index.sh` + `update-progress.sh` (state tracking)
4. [x] `telemetry.sh` (NDJSON append + rotation)
5. [x] `ask-or-default.sh` (wrapper auto-mode)
6. [x] `apply-naming.sh` (render templates branch/commit)
7. [x] `detect-test-commands.sh` (auto-detect test/lint)
8. [x] `check-mcp-required.sh` (validate MCPs + conflict resolution)
9. [x] `detect-platforms.sh` (runtime check auth)
10. [x] `setup-config.sh` (interactive wizard initial)
11. [x] `run-lifecycle-script.sh` (custom hooks workflow)

**Sortie:** scripts unitaires testables (`bats` shell tests recommandé).
