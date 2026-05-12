# Phase 11.5 — v0.2 documentation refactor (livré)

**Objectif:** séparer PRD archive (immuable) de doc fonctionnelle vivante (domain → user journey). Spec : `docs/docs-architecture.md`.

- [x] `meta.schema.json` v0.2 — drop `affine_*`, add `domains[]`, `impacted_journeys[]`, `prd.{page_id,url,path}`
- [x] `domains.schema.json` — cache domain + journey ↔ page IDs
- [x] `_shared/domains-state.sh` — CRUD idempotent (préserve journeys sur re-add)
- [x] `_shared/docs-adapter.sh` actions: `lookup-page`, `lookup-or-create-page`, `update-page-content`, `set-page-tags`, `create-page-tree`
- [x] `load-config.sh` injecte defaults `documentation.paths.{functional_root,prd_root}` + `auto_update_mode` + `auto_update_on_qa_success` quand `platform != "none"`
- [x] `/snap:init` step-00 capture `paths` + `auto_update_*` (skip si `platform=none`)
- [x] `/snap:doc-import` skill (6 steps) — bootstrap legacy doc (synthesize|copy|move)
- [x] `/snap:define` refactor — drop prd-global, archive PRD path date-based, `lookup-or-create` domain + journey
- [x] `/snap:doc-update` skill (5 steps) — auto post-QA hook (mode=diff|rewrite)
- [x] `/snap:qa` step-05 rollup ticket→feature `qa-validated` + auto-trigger `doc-update`
- [x] Tests: `test-domains-state.sh`, `test-docs-adapter.sh` v0.2 actions, `test-load-config.sh` paths injection, fixtures domains schema

**Sortie:** v0.2 ready. Pas de migration v0.1 → v0.2 (pilote uniquement).
