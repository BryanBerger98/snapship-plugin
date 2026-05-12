# Phase 0 — Setup repo

**Objectif:** scaffolding plugin + tooling dev.

- [x] Init repo `snap` (git, license MIT, README minimal)
- [x] Créer arbo squelette: `skills/`, `agents/`, `skills/_shared/`, `skills/_shared/templates/`, `skills/_shared/schemas/`
- [x] `.gitignore`: `_shared/telemetry.log*`, `.config-resolved.json`, `.qa-raw-*.json`
- [x] `plugin.json` brouillon (name, version 0.1.0, paths) — migration vers `.claude-plugin/plugin.json` en Phase 7 (schema officiel CC)
- [x] CI minimal: lint shell (`shellcheck`), validate JSON Schemas (`ajv-cli`), markdown lint
- [x] Structure docs `snap/` copiée depuis ce dossier (source vérité)

**Sortie:** repo public clone-able, structure vide validable CI.
