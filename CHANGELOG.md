# Changelog

All notable changes to snapship-plugin documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added — Wireframes export source dir

- **`wireframes.export_source_dir`** — nouvelle clé schema (string, défaut
  `~/Downloads`, tilde-expanded). Frame0 écrit toujours dans un **unique
  dossier OS** indépendamment du param `output_path` MCP ; le skill déplace
  ensuite le PNG depuis ce dossier vers
  `.claude/product/features/<id>/wireframes/`. Permet d'aligner la config
  avec l'OS si Frame0 exporte ailleurs (ex: `~/Desktop`).
- **`frame0-helper.sh move-export`** — nouvelle action **local-only** (jamais
  de descripteur MCP). Args `--filename=<basename>` + `--output-path=<dest>`.
  Compose `${export_source_dir}/${filename}`, `mkdir -p` la cible, `mv`. Exit
  0 succès, 1 si source introuvable (avec hint), 2 args invalides. Rejette
  les `--filename` contenant `/` ou `..` (anti-traversal).
- **`skills/wireframe/step-02-design.md`** — étape « Move export into the
  project » ajoutée après l'export PNG. Filename composé via
  `${feature_slug}-${screen_id}-${state}.png` (préfixé `feature_slug` pour
  rester unique dans `~/Downloads` partagés entre features).
- Dry-run : `move-export --dry-run` renvoie `{moved: false}` sans toucher au
  filesystem (cohérent avec le reste du pipeline wireframe).

### Changed — Plugin agents namespacing (breaking)

- **Préfixage `snap-` sur tous les agents bundlés du plugin** pour éviter les
  collisions avec les `.claude/agents/` du projet utilisateur. Claude Code
  donne la priorité aux agents du projet sur ceux du plugin lorsque les noms
  collident — sans préfixe, un agent `developer.md` ou
  `code-reviewer-technical.md` du projet écrasait silencieusement l'agent
  bundlé.
  - `agents/developer.md` → `agents/snap-developer.md`
  - `agents/code-reviewer-technical.md` → `agents/snap-code-reviewer-technical.md`
  - `agents/code-reviewer-functional.md` → `agents/snap-code-reviewer-functional.md`
  - `agents/code-reviewer-security.md` → `agents/snap-code-reviewer-security.md`
  - `agents/code-reviewer-qa.md` → `agents/snap-code-reviewer-qa.md`
  - Frontmatter `name:` aligné sur le nouveau nom de fichier.
- Refs mises à jour dans `skills/develop/` (step-00-init, step-02-prepare,
  step-03a-standalone) et `skills/qa/` (step-02-interpret, step-03-fix,
  step-04-retrigger). Note : `step-04-retrigger` utilisait des noms
  pré-existants incorrects (`reviewer-technical` au lieu de
  `code-reviewer-technical`) — corrigé en passant.
- Doc mises à jour : `docs/skills/develop.md`, `docs/structure.md`,
  `docs/plugin.md`, `docs/diagram.md`, `docs/roadmap.md`,
  `_shared/templates/docs-defaults/wireframes-gallery.md`.
- **Override utilisateur** : un projet qui veut surcharger un agent du plugin
  peut créer `.claude/agents/snap-<name>.md` (la priorité project > plugin
  reste effective sur le nom préfixé).

### Added — Templates customization

- **Système de templates customisables** — section `templates` dans
  `snapship.config.json` permet override par catégorie sans toucher au plugin
  (cf. `docs/templates.md`).
  - Schémas: `templates.tickets.{user_story,bug,epic}`,
    `templates.pr`, `templates.review_thread`, `templates.aggregated_feedback`
    (tous `string|null`, défaut `null` → bundlé).
  - Override relatif → résolu depuis project root ; absolu → tel quel.
  - Override pointant vers fichier inexistant → `resolve-template.sh` exit 2
    (échec explicite, pas de fallback silencieux).
- `_shared/resolve-template.sh` — helper unique de résolution
  (kind=ticket|pr|review-thread|aggregated-feedback). User override > bundlé.
  Exit 0 succès | 1 args invalides | 2 fichier introuvable.
- `_shared/templates/` — réorganisation **breaking** (anciens chemins retirés) :
  - `tickets/{user-story,bug,epic}/{github,gitlab,jira}.md` (9 templates,
    matrice type × plateforme)
  - `pr/{github,gitlab,default}.md`
  - `review-thread/{github,gitlab,jira}.md`
  - `aggregated-feedback.md` (blob interne fix-loop)
- `tickets-adapter.sh comment-pr` — nouvelle action pour poster un commentaire
  sur PR/MR (github via `gh pr comment`, gitlab via `glab mr note`). Args
  `--pr-id` + (`--comment` | `--body-file=PATH`). JIRA renvoie
  `{ok:false, error:"not_supported"}` exit 1 (pas de PR concept).
- `/ticket step-03-enrich` — classification heuristique du type ticket
  (`user-story` par défaut, `bug` si keywords/scope match, `epic` si agrège
  ≥3 child stories). Persisté sur chaque story pour pickup par step-04-format.
- `/ticket step-04-format` — résolution template par story via
  `resolve-template.sh --kind=ticket --type=$story_type --platform=$platform`.
- `/develop step-04-sync` — section C "Post review thread (best-effort)" :
  rendu via `templates.review_thread` resolved + posté via `comment-pr`.
- `/develop step-03a-standalone` — `aggregated_feedback` (injection dev
  fix-loop) rendu via `templates.aggregated_feedback` resolved.
- Tests :
  - `tests/test-resolve-template.sh` (25 assertions, 7 sections — args,
    bundled fallback × kinds, override ticket/pr/review-thread/agg, absolute
    path, missing file, null override).
  - Extension `test-load-config.sh` ([13]-[15] templates defaults injection +
    user override préservé + schema rejection).
  - Extension `test-tickets-adapter.sh` ([29]-[36] comment-pr dry-run, github
    via mock gh `pr comment`, gitlab via mock glab `mr note`, jira
    not_supported, missing pr-id / comment / body-file, no MCP descriptor
    leak).
  - Fixtures `tests/fixtures/valid/templates/` (5 templates custom),
    `tests/fixtures/invalid/config/bad-templates.json` (rejet schema).

### Removed — Templates customization (breaking)

- Champ `repository.pr_template_path` retiré (remplacé par `templates.pr`).
- Champs `documentation.templates.prd_global` /
  `documentation.page_naming.prd_global` retirés (alignés sur removal v0.2 du
  template `prd-global.md`).
- Anciens templates plats `_shared/templates/ticket-{platform}.md` et
  `_shared/templates/pr-default.md` supprimés (remplacés par layout
  hiérarchique `tickets/{type}/{platform}.md` et `pr/{platform}.md`).

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
