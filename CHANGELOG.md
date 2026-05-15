# Changelog

All notable changes to snapship-plugin documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
