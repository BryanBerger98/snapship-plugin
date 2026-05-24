# Changelog

All notable changes to snapship-plugin documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.2] — 2026-05-23

### Removed

- **Schema** : section `lifecycle_scripts` (12 hooks `pre_/post_` define→qa)
  retirée de `config.schema.json` — infrastructure orpheline. Le helper
  `run-lifecycle-script.sh` existait et validait, mais n'était appelé par
  aucun skill : zéro chemin d'exécution. Helper supprimé, défaut
  `load-config.sh`, boucle de warning et fixture `full-jira.json` nettoyés.
  Configs downstream contenant `lifecycle_scripts` : exécuter
  `jq 'del(.lifecycle_scripts)'` sur `snap.config.json`, sinon la validation
  schéma (`additionalProperties: false`) échouera.
- **Schema** : `documentation.auto_publish` et `documentation.page_naming`
  retirés de `config.schema.json` — clés jamais lues par un skill. La
  publication reste systématique et le nommage des pages suit désormais une
  convention fixe. Configs downstream : exécuter
  `jq 'del(.documentation.auto_publish, .documentation.page_naming)'` sur
  `snap.config.json`.
- **Schema** : `repository.http_url` et `repository.ssh_url` retirés de
  `config.schema.json` — purement informationnels, jamais consommés et
  déductibles de `git remote`. `setup-config.sh` cesse de les produire (flag
  `--repository-url` et helper `ssh_to_https()` supprimés). Configs downstream :
  exécuter `jq 'del(.repository.http_url, .repository.ssh_url)'` sur
  `snap.config.json`.

### Changed

- **Config désormais lue à l'exécution** — clés `🟠 Medium` de l'audit
  `audit-config-dead-keys` qui existaient au schéma mais n'étaient jamais
  consommées sont maintenant câblées dans les skills, avec valeurs par défaut
  documentées si la config est absente :
  - `defaults.lang` (`// "fr"`) — directive de langue de communication
    injectée dans chaque `step-00`.
  - `defaults.auto_mode` / `defaults.save_mode` / `defaults.branch_mode` /
    `defaults.economy_mode` — câblés via `ask-or-default.sh`, le gate
    `--save-mode` de `progress.sh`, et l'override `-e`/`--economy` de
    `load-config.sh` (force `ai.max_parallel_agents=1`,
    `develop.review_cycles_max=1`, `qa.qa_cycles_max=1`).
  - `develop.reviews.{technical,functional,security}.severity_threshold` —
    seuil par reviewer appliqué via le nouveau `severity-gate.sh`.
  - `develop.auto_apply_review_feedback` / `qa.auto_apply_qa_feedback`
    (`// true`) — branche auto-apply vs confirmation interactive.
  - `qa.wireframe_check.{mode,diff_threshold_pct,severity_on_mismatch}` et
    `qa.design_check.severity_on_mismatch` — appliqués via `severity-gate.sh`.
  - `wireframes.export_scale` (passé à `--scale` Figma, no-op frame0/penpot)
    et `wireframes.naming_pattern` / `design.naming_pattern` — rendus par le
    nouveau `screen-naming.sh`.
  - `documentation.templates.prd_feature` — chemin de template utilisateur
    propagé jusqu'au MCP via `docs-adapter.sh --template-id`.
  - `repository.default_branch` (`// "main"`) — branche de base des feature
    branches (`/develop` step-02) et cible PR/MR (`gh pr --base` /
    `glab mr --target-branch`, step-04), au lieu d'un `main` codé en dur.
  - `tickets.default_labels` (`// []`) — fusionnés (union dédupliquée) avec les
    labels par story à la création de tickets (`/ticket` step-05).
  - `testing.format_command` (skip si vide) — exécuté avant lint dans la
    boucle de validation `/develop` (step-02/03a) et le fix-loop `/qa`.
  - `tickets.jira.{project_key,default_issue_type,workflow_states,transitions}`
    — injectés dans le descriptor MCP Jira par `tickets-adapter.sh` (l'explicite
    `--issue-type` prime sur `default_issue_type` ; clés absentes omises).
  - `tickets.url` — fallback de lien browse dans l'index tickets (`/ticket`
    step-06) quand la plateforme ne renvoie pas d'URL (cas Jira MCP) ; l'URL
    réelle d'une plateforme (GitHub) prime toujours.

### Added

- **Helper** `severity-gate.sh` — comparaison testable de sévérités
  (`none<info<minor<major<critical`), modes `--mode=verdict|gate`.
- **Helper** `screen-naming.sh` (ex-`wireframe-naming.sh`) — rendu de nom de
  fichier depuis un `naming_pattern` (`{story_id}`, `{screen_name}`,
  `{state}`).
- **CLI** `load-config.sh -e` / `--economy[=true|false]` — override du
  `economy_mode`.
- **CLI** `progress.sh --save-mode=true|false` — `false` rend `start`/`step`/
  `finish` no-op (mode sans persistance).

## [1.2.1] — 2026-05-17

### Removed

- **Schema** : `tickets.github.project.number` et `tickets.github.project.url`
  retirés de `config.schema.json` — clés informationnelles jamais consommées
  par `apply-github-metadata.sh`. Migration `v1.0.0_to_v1.1.0.sh` cesse de les
  écrire ; `detect-github-fields.sh` cesse de les projeter. Configs downstream
  qui contiendraient ces clés héritées de l'ancienne migration : exécuter
  `jq 'del(.tickets.github.project.number, .tickets.github.project.url)'`
  sur `snap.config.json` avant le prochain chargement.

## [1.2.0] — 2026-05-16

**Product rename `snapship` → `snap`.** Config file, env file, manifest
directory, schema fields, and command namespace migrate in one breaking
release. Downstream projects must run `/snap:upgrade` to migrate.

The release also redesigns ticket hierarchy around four story types
(Epic / User Story / Task / Bug), moves persistence to the tracker as
single source of truth, introduces an ephemeral intra-run cache, and
ships two Haiku-backed subagents (classifier + digest) plus orchestrator
plumbing for the four existing reviewers.

### Breaking changes

- **Product rename** — `snapship.config.json` → `snap.config.json`,
  `.env.snapship` → `.env.snap`, `.snap/features/` → `.snap/stories/`.
  Migration handled idempotently by
  `skills/_shared/migrations/v1.1.0_to_v1.2.0.sh`.
- **Manifest field rename** — `feature_id` → `story_id` in every
  `meta.json`. `epic_link` dropped; replaced by `parent_epic_id` (null
  for standalone stories).
- **Tracker is the single source of truth** — `.snap/tickets/*.json`
  persistent cache **removed**. `/develop`, `/qa`, `/doc-update`, and
  `/fetch` now fetch ticket payloads live and use the ephemeral intra-run
  cache at `.snap/.runtime/<subject-id>/` (purged on EXIT).
- **`/develop --ticket=<platform_id>` mandatory** — drops the v1.1
  `--feature-id=` flag. Invocation is one-ticket-per-call; the skill
  fetches its payload from the tracker.
- **Schema `tickets.schema.json`** — `story_type` required, enum
  `{epic | user-story | task | bug}`. allOf rules: epic forbids
  `branch_name` and `commit_sha`; bug forbids a `bug` parent;
  user-story with `parent_epic_id` is the standard hierarchy edge.
  `target_version` accepts the new degenerate-version pattern.
- **Naming token rename** — `naming.commit_pattern` `{type}` →
  `{commit_type}`. The original `{type}` token shadowed `story_type`
  semantics ; `{commit_type}` makes the conventional-commit prefix
  explicit.

### Added

- **Ticket hierarchy** — Epic / User Story / Task / Bug story types with
  a strict parent-child matrix. Epic standalone forbidden; Bug→Bug
  forbidden; Task may attach to a User Story or Epic; Bug may attach to
  Task / User Story / Epic. See `docs/usage/concepts.md` for the matrix
  and examples.
- **Ephemeral runtime cache** — new helper
  `skills/_shared/cache-runtime.sh` (read / write / list / purge).
  Subject-id derived per skill (`story_id` for `/develop`+`/qa`,
  `prd_slug` for `/define`). Files: `ticket.json`, `parent.json`,
  `refs.json`, `digest.json`. Purged on shell EXIT trap.
- **Strict hierarchical push** — `/snap:ticket` now pushes in topological
  order: Epic → User Story → Task / Bug → Milestone → Version. Re-runs
  are idempotent: already-pushed nodes are detected via tracker probe.
- **Subagents** — two new Haiku-backed agents:
  - `snap-ticket-classifier` — decompose raw input → classify
    `story_type` → cluster into a hierarchy (auto mode) → format with
    `commit_type` + `branch_name_suggested`. Enforces parent-child
    matrix and returns a confidence score per ticket.
  - `snap-ticket-digest` — produces a consumer-aware brief
    (`developer` / `reviewer` / `designer` / `qa` profiles) from a
    tracker payload. Read-only. Lives at the orchestrator layer so
    parallel reviewers reuse a single brief (subagents do not nest).
  The four existing reviewers (`snap-code-reviewer-*`) now consume the
  digest's `brief_md` instead of a raw ticket payload.
- **`/define` modes** — `vision` / `journey` / `story`. Auto-detected
  from context, opt-in via `--mode=`. Vision and journey stay local;
  story emits a PRD.
- **Epic auto-close post-merge** — `/snap:develop` capability-gated
  step-99 closes the parent Epic on the tracker when every child
  User Story is `done` / `closed`. Disable per run with
  `--no-epic-close`; capability auto-detected per platform.
- **`/snap:upgrade` v1.1 → v1.2 migration** — idempotent, dry-run safe.
  Backs up `.snap/` to `.snap.bak-<timestamp>/`. Honours
  `SNAP_DECISIONS_JSON.drop_tickets_cache` (default `confirm`) and
  `rename_env` (default `auto`).

### Migration guide

1. `claude /snap:upgrade --check` — dry-run; previews every move,
   rename, and field change without writing.
2. `claude /snap:upgrade` — runs the v1.1 → v1.2 migration. Backup
   written to `.snap.bak-<timestamp>/`.
3. Review the residual sweep printed by `step-04-validate`: any leftover
   `snapship` / `feature_id` / `epic_link` references in non-snap files
   are surfaced as warnings (e.g. CI scripts, READMEs) for manual
   cleanup.
4. Re-run `/snap:init` if `snap.config.json.tickets` lacks the
   `story_type` mapping — the lazy self-heal in `step-00-init` will
   prompt for the missing block on the next `/snap:ticket`.

## [1.1.0] — 2026-05-15

### Added — native GitHub routing (Issue Type + Projects v2)

`/snap:ticket` no longer emits `type:`, `priority:`, `scope:`, `size:` labels
on github. Story attributes are routed to org-level Issue Types and Projects v2
single-select fields instead. Falls back to labels when Issue Type / Project
unavailable or unconfigured.

- **Config schema** — new `tickets.github` block (`enabled`, `issue_types`,
  `project.{id,number,url,title,fields}`, `label_fallback_prefixes`). Schema
  remains v1.0 backward-compatible: omitting the block means labels-only
  (v1.0 behaviour preserved). See
  `tests/fixtures/valid/config/github-native-routing.json`.
- **`skills/_shared/detect-github-fields.sh`** — read-only GraphQL probe that
  returns org Issue Types + Projects v2 + their single-select fields/options.
  Graceful when Issue Types feature is unavailable.
- **`skills/_shared/apply-github-metadata.sh`** — post-create orchestrator.
  Calls the adapter to set the Issue Type, add the issue to the configured
  Project, and apply the mapped single-select fields. Returns
  `residual_labels` for the caller to fall back on.
- **`skills/_shared/tickets-adapter.sh`** — three new github-only actions:
  `set-issue-type`, `add-to-project`, `set-project-field`. All other
  platforms (gitlab / jira) return `not_supported`.
- **`skills/ticket/step-02-decompose.md`** — stories carry `priority`,
  `estimated_size`, `scope`, `type` as structured top-level keys; no
  `type:value` labels written.
- **`skills/ticket/step-05-push.md`** — calls
  `apply-github-metadata.sh` after a successful create and applies any
  residual labels via the adapter `update` action.
- **`skills/ticket/step-00-init.md`** — lazy self-heal: when platform=github
  and `tickets.github` is missing from the resolved config, the run offers a
  one-shot detect + map prompt before continuing.

### Migration v1.0.0 → v1.1.0

- **`skills/_shared/migrations/v1.0.0_to_v1.1.0.sh`** — idempotent, dry-run
  safe. Honors `SNAP_DECISIONS_JSON.github_native_routing` (`enable` |
  `skip`), `github_project_link` (`auto` | `skip`), and optional explicit
  `issue_types_map` / `fields_map` / `project_selection`. Detection failure
  falls back to a minimal `{enabled:true}` block; the lazy self-heal in
  `step-00-init` re-prompts the user on the next `/snap:ticket`.
- `skills/_shared/migrations/registry.json` — bumped `schema_version` +
  `current_version` to `1.1.0`; migration entry added with two decisions.

### Tests

- `tests/test-detect-github-fields.sh` (28 assertions)
- `tests/test-apply-github-metadata.sh` (41 assertions)
- `tests/test-migration-v100-to-v110.sh` (33 assertions)
- `tests/test-tickets-adapter.sh` extended with 12 cases for the new actions.

### Fixed

- `detect-github-fields.sh` rejected bare `--repo=name` without slash (was
  splitting into owner=name / name=name silently). Now validates format.

## [1.0.0] — 2026-05-15

### Changed — documentation reorganised (`usage/` vs `contributing/`)

- **Top-level `docs/`** split into two entry points: `docs/usage/` (plugin
  users) and `docs/contributing/` (plugin developers).
- `docs/skills/` → `docs/usage/skills/`.
- `docs/plugin.md` → `docs/contributing/plugin-manifest.md` (renamed).
- `docs/docs-architecture.md` → `docs/usage/concepts.md` (renamed; it's
  a concepts doc for the user).
- New indexes: `docs/README.md` (hub), `docs/usage/README.md`,
  `docs/contributing/README.md`, `docs/usage/skills/README.md`.
- New internal orientation doc: `docs/contributing/architecture.md`
  (skill anatomy, state machine, `_shared/` helpers).
- Root `README.md` — Documentation section refactored into two tables
  (usage / contributing), badges + "you bring / SnapShip handles" framing.

### Initial release — remote-first workspace

First public release. The plugin chains six product skills
(`define → ticket → wireframe → design → develop → qa`) plus two doc
utilities, oriented around **remote platforms = sources of truth**. Local
is only used to pre-generate, validate, and stage before pushing to the
platforms (Notion/AFFiNE, Figma/Penpot/Frame0, Linear/Jira/GitHub/GitLab).
Ideally nothing is stored locally except references to the remote
resources.

- **`.snap/` layout** — split by type:
  - `.snap/manifests/{feature_id}.manifest.json`
  - `.snap/manifests/_taxonomy.json`
  - `.snap/tickets/{feature_id}.json` (local cache, persisted because referenced by /develop & /qa)
  - `.snap/wireframes/{feature_id}/` (staging before gallery push)
  - `.snap/designs/{feature_id}/` (staging before gallery push)
  - `.snap/queues/{feature_id}.{purpose}.json` (ephemeral queues for /develop & /qa)
  - `.snap/progress.json` (gitignored, `in_flight[]` + `steps[]`)
  - `.snap/.backup/{timestamp}/` (doc-import backups)
- **`_shared/` helpers**:
  - `progress.sh` — subcommands `start | step | finish | resume`.
  - `sync-push.sh` / `sync-fetch.sh` (write-through outbox to platforms).
  - `load-config.sh` returns the resolved config on stdout.
  - `setup-snap-dir.sh`, `taxonomy-state.sh`, `telemetry.sh log`.
- **`/develop` skill** — session-only loop (standalone or session).
- **`/snap:upgrade` skill** — framework migration with `.snap.bak-{timestamp}/` backup.
- **`/snap:fetch` skill** — refresh local caches from the platforms (replay
  refs stored in the manifest).
- **Manifest state machine** — transitions per terminal step:
  `defined → ticketed → wireframed → designed → developed → qa-validated →
  shipped`.
- **`.gitignore`** — whitelist `.snap/manifests/` + `.snap/tickets/`, ignore
  the rest (caches, queues, telemetry, progress, backups, staging).
- **CI** — `.github/workflows/validate.yml` validates scripts + tests.

### Templates repo-native (`.github` / `.gitlab`)

- **`/ticket` and `/develop` reuse host templates.** Before the bundled
  fallback, the plugin scans GitHub/GitLab conventions:
  `.github/ISSUE_TEMPLATE/*.md` (+ `.github/ISSUE_TEMPLATE.md`),
  `.gitlab/issue_templates/*.md`, `.github/PULL_REQUEST_TEMPLATE.md`
  (+ root, `docs/`, directory form), `.gitlab/merge_request_templates/*.md`.
- **`skills/_shared/detect-repo-templates.sh` helper** — detects the
  repo-native template (`--kind=ticket|pr`), maps file name to type
  (`bug`/`epic`/`user-story`), ignores YAML issue forms
  (`.yml`/`.yaml`). JIRA: no repo-native convention → always empty.
- **`resolve-template.sh` emits JSON** `{path, source, render_mode}`.
  Resolution order: **config override > repo-native > bundled**.
  `render_mode=mustache` (config/bundled, rendered by `render-template.sh`)
  or `scaffold` (repo-native, markdown skeleton filled section by section
  while keeping the house style).
- **`templates.use_repo_native` config key** (boolean, default `true`).
  `false` → entirely ignore the repo-native layer. An explicit override
  (`templates.tickets.*`, `templates.pr`) always wins.
- **`review-thread` and `aggregated-feedback`** stay on config override or
  bundled: these are internal snap artifacts, no repo-native convention.

### `/design` — hi-fi mockups

- **`/design` does one thing only: hi-fi mockups.** The design system is
  managed outside the plugin.
- **`/design` input** — takes a `<ticket-id|feature-id>` (like `/develop`
  and `/qa`) and builds mockups from what the ticket asks for. A
  ticket id targets one ticket; a feature id batches all UI tickets.
- **`/design figma` uses the same `figma-helper.sh`** and the same Desktop
  Bridge plugin as `/wireframe figma` — unified Figma surface, one helper
  to maintain.
- **`/design` pipeline** — `step-00-init` → `step-01-source-resolve`
  → `step-02-mockup` → `step-03-gallery` → `step-04-link`.
- **Optional DS read** — `design.mode_defaults.design_system_source`
  (`none|file|auto`): the configured DS file can be **read** as a component
  reference, never written.
- **Note** — the **Desktop Bridge plugin** (Figma plugin, WebSocket channel
  for `figma-console-mcp`) is required for the Figma flows.

### Secrets isolated via `.env.snapship`

- **Figma token loaded from `.env.snapship`** (project root, gitignored)
  instead of the shell env directly. `/design` figma + `/wireframe` figma
  skills call `skills/_shared/load-env.sh --project-root="$PWD"
  --key=<NAME>` then export the value for `figma-console-mcp`. Default key
  `FIGMA_ACCESS_TOKEN` (override via `design.figma.token_env` /
  `wireframes.figma.token_env`).
- **`skills/_shared/load-env.sh` helper** — simple KEY=VALUE parser
  (`#` comments, quotes stripped, no shell substitution).
  `--key=NAME` mode returns value or exits 1. No-`--key` mode dumps all
  (usable with `eval`).
- **`.gitignore`** — `.env.snapship` + `.env.snapship.*` (per-project
  secrets must never be committed).
- **Rationale**: the commit-friendly config (`snapship.config.json`) must
  not contain secrets. Usual `.env.<name>` pattern for isolated per-project
  secrets (Vercel, Next.js, etc.).
