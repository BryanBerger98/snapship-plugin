# Changelog

All notable changes to snapship-plugin documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added (v0.2 — breaking)

- **Doc architecture refactor** — PRD = archive immuable, doc fonctionnelle = source vivante (cf. `docs/docs-architecture.md`).
  - PRD path: `{prd_root}/{YYYY}/{MM-YYYY}/{NN-feature}` (figé post-ship, tags domaines).
  - Doc fonctionnelle: arbre `{functional_root}/{domain}/{journey}` (mise à jour incrémentale post-QA).
- `/snap:doc-import` skill — bootstrap d'un projet existant: import doc legacy AFFiNE/Notion, classification `lookup-or-create-page` `{domain}/{journey}`, hydrate `domains.json`. 6 steps (init/discover/classify/normalize/publish/finish), cache éphémère `.doc-import-cache/`.
- `/snap:doc-update` skill — propage l'état post-QA aux pages fonctionnelles impactées. Modes `diff` (patch sections impactées) ou `rewrite` (regénération complète, override auto si page vide). 5 steps (init/collect/update/publish/finish), prompts AI "describe end state, never reference PRD/tickets/git". Auto-trigger via `SNAP_NEXT_SKILL=` post-QA.
- `domains.schema.json` + `_shared/domains-state.sh` — CRUD persistant `.claude/product/domains.json` (source de vérité ID pour idempotent `lookup-or-create`). Subcommands: init, add-domain, add-journey, get-domain, get-journey, list-domains, list-journeys, has-domain, has-journey, validate (ajv).
- `docs-adapter.sh` — 5 nouvelles actions write idempotent: `lookup-page`, `lookup-or-create-page`, `update-page-content`, `set-page-tags`, `create-page-tree`. Émission MCP descriptor (exit 10), `--dry-run` short-circuit writes seulement.
- `/snap:define` step-05-publish — pousse PRD archive (`{YYYY}/{MM-YYYY}/{NN-feature}` via `create-page-tree` + `apply-template`) ET garantit `lookup-or-create-page` pour chaque `{domain}/{journey}` impacté. Met à jour `domains.json`.
- `/snap:qa` step-05-finish — rollup `feature.state → qa-validated` quand tous tickets validés (mutation jq + ajv-validate post). Auto-trigger `/snap:doc-update` via `SNAP_NEXT_SKILL=doc-update --feature=${id} -a` si `documentation.auto_update_on_qa_success: true` (gated par flag `--no-doc-update`).
- Config additions: `documentation.paths.{functional_root,prd_root}`, `documentation.auto_update_mode` (`diff|rewrite`), `documentation.auto_update_on_qa_success` (bool). Defaults injectés via `load-config.sh` (deep-merge).
- Fixtures v0.2: `tests/fixtures/valid/meta/{full,v02-defined}.json`, `valid/domains/{empty,full}.json`, `invalid/meta/{bad-domain-slug,legacy-affine-field}.json`, `invalid/domains/{missing-page-id,journey-missing-page-id}.json`.
- Tests: `tests/test-domains-state.sh` (22 assertions, 8 sections — idempotence add-domain preserves journeys, ajv validate). Extension `test-docs-adapter.sh` (+ assertions [25]-[33] couvrant 5 actions v0.2 + dry-run write-only). Extension `test-load-config.sh` ([10]-[12] paths defaults injection + override préservé incluant `auto_update_on_qa_success: false`). `validate-schemas.sh` étend à `domains/`.

### Changed (v0.2 — breaking)

- `meta.json` — schema breaking: drop `affine_page_id`, `affine_url`, `affine_wireframes_page_id`. Ajoute `domains: [string]`, `impacted_journeys: [{domain, journey_slug}]`, `prd: {page_id, url, path}`. `additionalProperties: false` rejette désormais les anciens champs.
- `/snap:ticket` step-01-load — lit `prd.page_id` / `prd.url` (au lieu des legacy `affine_*`).
- Templates docs — `prd-feature.md` étendu (variables change-request complètes: `feature_status`, `target_release`, `solution_overview`, `in_scope`/`out_of_scope`, blocs `acceptance_criteria`, `user_segments`, `edge_cases`, `error_states`, `wireframes`, `tickets`, `open_questions`).

### Removed (v0.2 — breaking)

- Template `prd-global.md` retiré — la "global PRD" est remplacée par les domain pages générées idempotemment via `lookup-or-create-page` (`/snap:doc-import` ou `/snap:define` publish).
- Champs `meta.json.affine_*` (cf. Changed). Pas de migration — v0.1 = pilote dogfood seul.

### Fixed

- `load-config.sh` — bug deep-merge defaults: `// null` traitait `false` comme null, écrasait l'override user explicite (`auto_update_on_qa_success: false` revertait à `true`). Fix: `if (.documentation | has("key")) | not then` (pattern aligné sur le block `paths`). Test `test-load-config 12.4` couvre la régression.

### Added

- Plugin manifest at `.claude-plugin/plugin.json` (Claude Code schema-conforme).
- `.mcp.json` racine bundle `code-review-graph` MCP — auto-start quand plugin activé.
- `NOTICE` documentant attributions community MCPs (code-review-graph, affine-mcp-server, frame0-mcp-server, playwright-mcp).
- `/snap:init` skill: bootstrap workspace (config wizard + scaffold `.claude/product/`). Détection MCP/git, AskUserQuestion drive, autonomous mode (`-a`), `--force` overwrite.
- `/qa` skill complet: pipeline 6 étapes (init→collect→interpret→fix→retrigger→finish), regression scope=impacted via code-review-graph (fallback tests-only), wireframe diff Playwright vs Frame0 PNG, code-reviewer-qa agent, dev↔qa cycle bounded, opt-in retrigger des 3 reviewers /develop.
- `/develop` skill complet: standalone + loop session/daemon, 3 reviewers parallèles (technical/functional/security), atomic commits, fail_strategy (next-ticket/stop/retry+fallback).
- `/wireframe` skill complet: filtre UI tickets, génération multi-écrans Frame0, AFFiNE gallery embed.
- `/ticket` skill complet: décomposition PRD → tickets, enrichissement explore-codebase, push plateforme adapter (github/gitlab/jira).
- `/define` skill complet: setup wizard initial, brainstorm PRD interactif, AFFiNE storage.
- 4 reviewer agents: technical, functional, security, qa.
- E2E tests: define, ticket, wireframe, develop, qa (135 deterministic checks).

### Changed

- `tickets.json` schema étendu pour cycle /qa: status enum + `qa-validated`, `acceptance_criteria.ac_id`, `qa_cycles_used`, `qa_last_severity`, `qa_last_flaky_verdict`, `qa_blocked`, `qa_retriggered`, `qa_retrigger_severity`, `qa_retrigger_verdicts`, `updated_at`.
- `/define` ne crée plus `snapship.config.json` — responsabilité déplacée vers `/snap:init`. Tous les skills (define/ticket/wireframe/develop/qa) exit early avec pointer vers `/snap:init` si config absente.
- `setup-config.sh --write` génère maintenant `$schema` avec URL github raw (portable cross-installs) au lieu d'un chemin relatif au plugin (cassé une fois plugin installé hors repo).

### Removed

- Legacy `plugin.json` racine remplacé par `.claude-plugin/plugin.json`.
- Champs custom invalides (`skills_path`, `agents_path`, `shared_scripts_path`, `schemas_path`, `templates_path`, `commands` array d'objets, `mcp_servers`) — non supportés par schéma plugin CC.

## [0.1.0] — TBD

Premier scaffold pré-marketplace. Cible: validation interne projet pilote (Phase 8 dogfooding) avant publication marketplace `bryanberger/claude-plugins`.
