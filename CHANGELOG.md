# Changelog

All notable changes to snapship-plugin documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
- Removed (obsolete): `docs/release-notes-v1.0.0.md` (redundant with
  CHANGELOG + GitHub Release), `docs/coverage.md` (6 obsolete lines
  redundant with README), `docs/dogfooding-v0.1.0.md` (v0.1 notes
  replaced by CHANGELOG + roadmap removed).
- Root `README.md` — Documentation section refactored into two tables
  (usage / contributing), badges + "you bring / SnapShip handles" framing.

### Changed — v1.0.0 refactor (BREAKING)

Major rework oriented around **remote platforms = sources of truth**. Local
is only used to pre-generate, validate, and stage before pushing to the
platforms (Notion/AFFiNE, Figma/Penpot/Frame0, Linear/Jira/GitHub/GitLab).
Ideally nothing is stored locally except references to the remote
resources.

- **`.snap/` layout reorganised** — split by type, no more monolithic
  `features/{slug}/`:
  - `.snap/manifests/{feature_id}.manifest.json` (replaces `features/{slug}/meta.json`)
  - `.snap/manifests/_taxonomy.json` (replaces `.snap/domains.json`)
  - `.snap/tickets/{feature_id}.json` (local cache, persisted because referenced by /develop & /qa)
  - `.snap/wireframes/{feature_id}/` (staging before gallery push)
  - `.snap/designs/{feature_id}/` (staging before gallery push)
  - `.snap/queues/{feature_id}.{purpose}.json` (ephemeral queues for /develop & /qa)
  - `.snap/progress.json` (replaces `progress.md`, gitignored, `in_flight[]` + `steps[]`)
  - `.snap/.backup/{timestamp}/` (doc-import backups)
- **`_shared/` helpers refactored**:
  - `progress.sh` (replaces `update-progress.sh` + `resume-state.sh`) — subcommands
    `start | step | finish | resume`.
  - `sync-push.sh` / `sync-fetch.sh` (write-through outbox to platforms).
  - `load-config.sh` now returns the resolved config on stdout (no more
    `.config-resolved.json` cache).
  - `setup-product-dir.sh` → `setup-snap-dir.sh`.
  - `domains-state.sh` → `taxonomy-state.sh`.
  - `telemetry.sh emit` / `append` → `telemetry.sh log` (unified signature).
- **`/develop` skill — drop daemon mode.** No more `--loop=daemon`. Loop is
  session-only.
- **`/snap:upgrade` skill (new)** — framework migration v0.6.0 → v1.0.0
  with `.snap.bak-{timestamp}/` backup.
- **`/snap:fetch` skill (new)** — refresh local caches from the
  platforms (replay refs stored in the manifest).
- **Manifest state machine** — transitions per terminal step:
  `defined → ticketed → wireframed → designed → developed → qa-validated →
  shipped`.
- **`.gitignore`** — whitelist `.snap/manifests/` + `.snap/tickets/`, ignore
  the rest (caches, queues, telemetry, progress, backups, staging).
- **CI** — `.github/workflows/validate.yml` workflow updated for the
  new script/test names.

### Added — templates repo-native (`.github` / `.gitlab`)

- **`/ticket` and `/develop` reuse host templates.** Before the bundled
  fallback, the plugin scans GitHub/GitLab conventions:
  `.github/ISSUE_TEMPLATE/*.md` (+ legacy `.github/ISSUE_TEMPLATE.md`),
  `.gitlab/issue_templates/*.md`, `.github/PULL_REQUEST_TEMPLATE.md`
  (+ root, `docs/`, directory form), `.gitlab/merge_request_templates/*.md`.
- **New `skills/_shared/detect-repo-templates.sh` helper** — detects the
  repo-native template (`--kind=ticket|pr`), maps file name to type
  (`bug`/`epic`/`user-story`), ignores YAML issue forms
  (`.yml`/`.yaml`). JIRA: no repo-native convention → always empty.
- **`resolve-template.sh` now emits JSON** `{path, source, render_mode}`
  instead of just a path. Resolution order: **config override >
  repo-native > bundled**. `render_mode=mustache` (config/bundled, rendered by
  `render-template.sh`) or `scaffold` (repo-native, markdown skeleton filled
  section by section while keeping the house style).
- **New `templates.use_repo_native` config key** (boolean, default `true`).
  `false` → entirely ignore the repo-native layer. An explicit override
  (`templates.tickets.*`, `templates.pr`) always wins.
- **`review-thread` and `aggregated-feedback`** stay on config override or
  bundled: these are internal snap artefacts, no repo-native convention.
- **Tests** — new `tests/test-detect-repo-templates.sh` (27 cases),
  `tests/test-resolve-template.sh` extended for JSON output + precedence +
  `use_repo_native=false` (37 cases). CI step added.
- **Docs** — `docs/templates.md`, `docs/config.md`, `docs/scripts.md`,
  `docs/skills/ticket.md`, `docs/skills/develop.md`, `docs/decisions.md`.

### Removed — `/design` reduced to mockups, Bridge CLI tooling removed (breaking)

- **`/design` now does one thing only: hi-fi mockups.**
  Removed `ds-extract` / `ds-init` / `ds-update` modes. The design
  system is now managed outside the plugin.
- **`/design` input** — takes a `<ticket-id|feature-id>` (like `/develop`
  and `/qa`) and builds mockups from what the ticket asks for. A
  ticket id targets one ticket; a feature id batches all UI tickets.
- **Removed the `bridge-ds` CLI** (`noemuch/bridge` repo) and all its
  tooling: `figma-bridge-helper.sh` + `design-mode-resolver.sh` helpers,
  `design-system-defaults/` templates, `test-figma-bridge-helper.sh` +
  `test-design-mode-resolver.sh` tests, `step-01-ds-bootstrap.md` +
  `step-01b-ds-extract.md` steps.
- **`/design figma` uses the same `figma-helper.sh`** and the same Desktop
  Bridge plugin as `/wireframe figma` — unified Figma surface, one helper
  to maintain.
- **Config** — keys removed: `design.extract` (entire block),
  `design.figma.bridge_kb_path`, `design.figma.bridge_transport`. Schema
  `additionalProperties:false` rejects the old keys.
- **`/design` pipeline renumbered** — `step-00-init` → `step-01-source-resolve`
  → `step-02-mockup` → `step-03-gallery` → `step-04-link`.
- **Optional DS read** — `design.mode_defaults.design_system_source`
  (`none|file|auto`): the configured DS file can be **read** as a component
  reference, never written.
- **Note** — the **Desktop Bridge plugin** (Figma plugin, WebSocket channel
  for `figma-console-mcp`) is still required; it has no link to the
  removed `bridge-ds` CLI (two distinct entities sharing the name).
- **Docs** — `docs/skills/design.md`, `docs/config.md`, `docs/mcp-refs.md`,
  `docs/decisions.md`, `docs/README.md`, `README.md`, `plugin.json` updated.

### Changed — secrets isolated via `.env.snapship`

- **Figma token loaded from `.env.snapship`** (project root, gitignored)
  instead of the shell env directly. `/design` figma + `/wireframe` figma
  skills call `skills/_shared/load-env.sh --project-root="$PWD"
  --key=<NAME>` then export the value for `figma-console-mcp`. Default key
  `FIGMA_ACCESS_TOKEN` (override still via
  `design.figma.token_env` / `wireframes.figma.token_env`).
- **New `skills/_shared/load-env.sh` helper** — simple KEY=VALUE parser
  (`#` comments, quotes stripped, no shell substitution).
  `--key=NAME` mode returns value or exits 1. No-`--key` mode dumps all
  (usable with `eval`). Tests: 12/12 pass.
- **`.gitignore`** — adds `.env.snapship` + `.env.snapship.*` (per-project
  secrets must never be committed).
- **Docs** — `docs/config.md` new section "Secrets: `.env.snapship`"
  (format + resolution + common errors). `docs/skills/design.md` +
  `docs/skills/wireframe.md` updated to point to the new flow.
- **Rationale**: the commit-friendly config (`snapship.config.json`) must
  not contain secrets. Usual `.env.<name>` pattern for isolated per-project
  secrets (Vercel, Next.js, etc.).

## [0.6.0] — 2026-05-13

### Added — `/design --mode=ds-extract` (LLM-driven React → YAML CSpec one-shot)

- **New `ds-extract` mode** on the `/design` skill — Claude reads the
  existing React components under `design.extract.source` and emits
  the YAML CSpec directly under `design-system/specs/`. One-shot
  bootstrap code → YAML → Figma. After init, **Figma = source of truth**
  (no reverse sync). To propagate Figma → code, use Figma Dev
  Mode + Code Connect (out of scope).
- **LLM-driven, stack-agnostic.** No dedicated parser, no Node CLI,
  no build. Works on Tailwind+cva, styled-components, CSS Modules,
  MUI, vanilla CSS, and custom patterns (HOC, render props). Accepted
  trade-off: non-deterministic, but reviewed by user before Figma push.
- **Explicit-only mode** — `ds-extract` is never auto-resolved by
  `step-00`. Must be passed via `--mode=ds-extract` explicitly, to
  avoid re-generating the YAML after Figma has become source of
  truth (otherwise `ds-update` would clobber design edits).
- **`--chain-init` flag** — automatically chains into `ds-init` after
  extract (full pipeline code → YAML → Figma in one command).
- **Atomic/molecular/organism classification** via import graph
  analysis (fixed-point) with comment override
  `// @ds-category: organism`.
- **If Tailwind detected** — Claude reads `tailwind.config.{ts,mjs,cjs,js}`
  to map classes → tokens (`bg-brand-500` → `{colors.brand.500}`).
- **`skills/design/step-01b-ds-extract.md`** (new step) — LLM-driven
  instructions: source validation, Figma pre-flight confirmation, component
  reading, classification, YAML emission, persists
  `.design-cache.json` `extract.ran_at` flag, chains into step-01 if
  `--chain-init`.
- **`design.extract` config** (opt-in) — three keys only:
  `source` (`src/components`), `out` (`design-system/specs`),
  `category_override_marker` (`@ds-category`). Defaults resolved by
  `load-config.sh` only if block present (skill disabled otherwise).
- **`setup-config.sh`** — new wizard flags
  `--design-extract-opt-in=true|false` + granular flags
  `--design-extract-source`, `--design-extract-out`. Tests: 35/35 pass.
- **`skills/design/SKILL.md`** + `step-00-init.md` updated — `ds-extract`
  added to the modes table, arg parsing supports `--mode=ds-extract` +
  `--chain-init`, mode resolver short-circuit (skip auto-detect for
  `ds-extract`), routing `step-00` → `step-01b` → optionally `step-01`.

### Added — Schema config v0.6

- **`design.extract`** added to the JSON Schema (`config.schema.json`) with
  `additionalProperties: false`, inline defaults. 30/30 schema tests pass.
- **`load-config.sh`** — `design.extract` block resolved only if present
  in the config (skill disabled by default). 47/47 tests pass.

### Docs

- **`docs/skills/design.md`** — `ds-extract` section added with
  LLM-driven flow, opt-in config, Figma-source-of-truth post-init constraint.
- **`docs/config.md`** — `design.extract` block documented.
- **`docs/decisions.md`** — "v0.6 — ds-extract one-shot React → YAML"
  decision added (rationale LLM-driven vs AST parser, explicit-only, no reverse sync).
- **`docs/roadmap/phase-07.6-ds-extract.md`** — Phase 7.6 spec.

## [0.5.0] — 2026-05-13

### Added — `/design` skill (3 modes: ds-init, ds-update, mockup)

- **New `/design` skill** — optional, parallel or sequential to
  `/wireframe`. 6 end-to-end steps (init → ds-bootstrap → source-resolve →
  mockup → gallery → link). Mode auto-resolved at step-00:
  - `ds-init` — bootstrap design system from
    `_shared/templates/design-system-defaults/{atomic,molecular,organism}.yaml`.
  - `ds-update` — diff specs vs file → patch in place (upsert components
    by name, `.design-cache.json` cache with `specs_hash`).
  - `mockup` — per `(screen_id, state)`, hi-fi frame applying DS
    components, asset export, link to UI tickets.
- **Supported platforms**: `penpot` (reused `penpot-helper.sh` helper,
  skill-controlled fidelity) or `figma` (`figma-bridge-helper.sh` helper via
  `bridge-ds` CLI). `frame0` excluded (low-fi only).
- **Auto-link wireframes ↔ design** — if `wireframes.platform == design.platform`
  AND wireframes binding set AND `design.{plat}.{file_id|file_key}` null →
  step-00 `AskUserQuestion` proposes reusing the same file.
- **Mode resolver** (`_shared/design-mode-resolver.sh`) — heuristic by
  signal (empty DS file binding + YAML defaults → `ds-init`; binding set +
  spec diff → `ds-update`; `--feature` or unflagged UI tickets → `mockup`).
  Ambiguity → `AskUserQuestion`.
- **Preflight**: MCP (`check-mcp-required.sh --skill=design`),
  Penpot (`get-current-file` vs `design.penpot.file_id`),
  Figma (token env + `figma.fileKey` vs `design.figma.file_key` +
  `bridge-ds` reachable).
- **Bundled templates**: `_shared/templates/docs-defaults/design-gallery.md`,
  `_shared/templates/design-system-defaults/{atomic,molecular,organism}.yaml`.
- **`figma-bridge-helper.sh`** (new) — surface: `ds-init`, `ds-update`,
  `mockup-compile`, `extract-ds`, `export-shape`. Backend: `bridge-ds compile`
  CLI invocation (YAML CSpec → JS Plugin API conforming to design system) +
  injection per transport (`official` = `figma-console-mcp`'s `figma_execute`;
  `console` = `.js` write + manual DevTools paste). Tests:
  `tests/test-figma-bridge-helper.sh` (76/76 pass).
- **Tickets schema** — added optional fields `design_screen`, `design_url`,
  `design_mode` (`mockup|reused`) on `tickets[]`.
- **`pre_design` / `post_design` lifecycle hooks** added to
  `lifecycle_scripts` enum.
- **`/develop` step-00** — designer-handoff banner if `tickets[].design_url`
  present (non-blocking if absent).
- **`/qa` step-04** — `design_check` option (opt-in
  `qa.design_check.enabled`). Mode `asset-presence` (default) or `playwright`
  (future).
- **`/snap:doc-update`** — ingests design assets in addition to wireframes in
  journey bundles.
- **`resume-state.sh --skill=design`** — per-mode state (`ds-init`,
  `ds-update`, `mockup` resume independently).
- Tests: new suites `test-design-e2e.sh` (19/19),
  `test-design-mode-resolver.sh` (15/15).

### Added — Figma platform for `/wireframe`

- **`wireframes.platform`** accepts `"figma"` (in addition to `"frame0"` /
  `"penpot"`). `figma-helper.sh` helper exposes the same surface as the
  other helpers (`create-page`, `get-page`, `update-page`, `delete-page`,
  `list-pages`, `add-shapes`, `export-png`, `get-current-file`, plus
  `save-export` to decode the inline base64 returned by
  `figma_execute`).
- **Backend** — single MCP `figma-console-mcp` (southleft, MIT, ~100 tools)
  via `figma_execute` tool (raw JS Plugin API, returns JSON of created nodes).
  Colours converted `#hex` → `{r,g,b}` 0–1 helper-side (Figma
  convention). Exports via `node.exportAsync()` return inline base64 →
  `save-export` decodes and writes to disk.
- **User prerequisites** — Figma Desktop running, "Desktop Bridge" plugin
  installed (WebSocket channel ports 9223–9232), `$FIGMA_ACCESS_TOKEN` (or
  variable named by `wireframes.figma.token_env`), Node.js 18+.
- **step-00 preflight** — `get-current-file` compares `figma.fileKey` to
  `wireframes.figma.file_key`. Mismatch → clear halt. Empty →
  AskUserQuestion flow (Save to config).
- Tests: `tests/test-figma-helper.sh` (116/116 pass).

### Changed — Config schema nested per-platform (breaking)

- **`wireframes`**: platform-specific keys become nested blocks
  (`wireframes.{frame0,penpot,figma}`). `additionalProperties: false`
  rejects the old flat keys.
- **`design`**: new section parallel to `wireframes`. Optional;
  absent = `/design` skill disabled.
- **Context-agnostic helpers** — `frame0-helper.sh`, `penpot-helper.sh`,
  `figma-helper.sh`, `figma-bridge-helper.sh` no longer read the config.
  All params (`--api-port`, `--file-id`, `--file-key`, `--export-dir`,
  `--format`, `--kb-path`, `--transport`, `--token-env`) are passed
  explicitly skill-side. `step-00` resolves the nested values and persists
  them in the skill state.
- **`setup-config.sh` wizard** — opt-in design sections.
- **`load-config.sh`** — defaults injected on the nested blocks
  (`wireframes.figma.token_env`, `design.export_format`,
  `design.naming_pattern`, `design.mode_defaults.*`, `design.figma.*`,
  `design.penpot.design_system_page`). Reads of v0.4 flat keys
  removed.

#### Migration mapping v0.4 → v0.5

| v0.4 (flat)                       | v0.5 (nested)                        |
| --------------------------------- | ------------------------------------ |
| `wireframes.frame0_api_port`      | `wireframes.frame0.api_port`         |
| `wireframes.export_source_dir`    | `wireframes.frame0.export_source_dir`|
| `wireframes.penpot_export_dir`    | `wireframes.penpot.export_dir`       |
| `wireframes.penpot_file_id`       | `wireframes.penpot.file_id`          |
| `wireframes.penpot_file_name`     | `wireframes.penpot.file_name`        |
| —                                 | `wireframes.figma.{file_key,file_name,token_env}` (new) |
| —                                 | `design.*` (new section)             |
| —                                 | `tickets[].design_screen / design_url / design_mode` (new) |

### Added — Migration script v0.4 → v0.5

- **`scripts/migrate-config-v04-to-v05.sh`** (jq one-shot, not bundled
  at runtime). Reads `snapship.config.json` v0.4, writes nested v0.5. Idempotent
  (no-op if already v0.5). `.bak` backup created.
- Tests: `tests/test-migrate-config-v04-to-v05.sh` (17/17 pass); covers
  idempotent no-op, full mapping, post-migration validation against
  v0.5 schema.

### Changed — Helpers shared structured metadata

- **`telemetry.sh`** and **`update-progress.sh`** now accept
  `--extra=JSON` (JSON object merged into the NDJSON event/log). Lets
  steps log structured context (design mode, specs_count,
  linked_tickets, ...) without inflating the API with arguments.

### Fixed — `/wireframe` exports a single asset per page (config-driven format)

- **step-02-design.md**: explicit "Exactly one export per page" added
  + dedicated "Resolve export format (once, at start of step)" block that reads
  `config.wireframes.export_format` once and stores it in `$fmt`.
- `export-png` invocation examples freed from hardcoded `--format=png`;
  the helper falls back on the config automatically. "DO NOT pass
  --format here" note blocks any drift.
- File extension derived from `$fmt` (`${page_title}.${fmt}`) instead
  of hardcoded `.png` — the agent can no longer guess it should also
  produce `.svg` to match the config.
- **Why**: a recent run had produced PNG and SVG simultaneously because
  the doc hardcoded `--format=png` while the config said `svg`. The
  model interpreted the divergence by exporting both. Resolving once
  from the config makes the format single-source.

### Changed — `/wireframe` skill platform-neutral wording

- **SKILL.md**: description and pipeline reworded without exclusive mention
  of Frame0. New "Supported platforms" table makes the
  `wireframes.platform` → helper mapping explicit. Outputs/args neutralised.
- **step-00-init.md**: Frame0 (§5.a) and Penpot (§5.b) preflights clearly
  separated under dedicated headings instead of mixed prose.
- **step-02-design.md**: PNG export split into §3.a blocks (frame0, HTTP
  bypass + full format enum) and §3.b (penpot, `export_shape` absolute
  `filePath` + restricted format enum). Failure handling split between generic
  and platform-specific.
- **Why**: avoid ambiguities when the user switches platforms — each
  named section unambiguously points to the expected behaviour for its
  engine.

### Added — Penpot file binding preflight

- **`wireframes.penpot_file_id` + `penpot_file_name`** (config schema) —
  UUID + human-readable name of the targeted Penpot file. The Penpot MCP
  **cannot open a file programmatically**: the targeted file = the one open
  in the browser tab where the Penpot MCP plugin is loaded and connected.
- **`penpot-helper.sh get-current-file`** (new) — argument-less action;
  emits an `execute_code` descriptor returning `{id, name}` from
  `penpot.currentFile`. The skill's step-00 calls it during preflight.
- **`step-00-init.md` 5b** — Penpot file binding preflight:
  - Calls `get-current-file`. If "no plugin connected" → halt with
    instruction (open file + load plugin + connect).
  - If `penpot_file_id` is set in config → compare. Mismatch = halt with
    a clear message (expected vs got).
  - No `penpot_file_id` → `AskUserQuestion` confirms + offers
    "Save to config" to persist the binding.
- **Tests**: +6 (`get-current-file` action JS shape, exit code, descriptor
  shape, read-action behaviour under dry-run). 66/66 pass.

### Added — Penpot wireframe platform support

- **`wireframes.platform`** now accepts `"penpot"` in addition to `"frame0"`
  (config schema). The `/wireframe` skill dispatches to the matching helper
  based on the config resolved at step-00.
- **`skills/_shared/penpot-helper.sh`** (new) — mirrors the
  `frame0-helper.sh` API (actions `create-page`, `get-page`, `update-page`,
  `delete-page`, `list-pages`, `add-shapes`, `export-png`). Each action
  emits an MCP descriptor (exit 10) targeting the appropriate Penpot tool:
  - All CRUD goes through the `execute_code` MCP tool with a JS blob
    built helper-side (uses `penpot.createPage()`, `createRectangle()`,
    `createText()`, `createEllipse()`, `penpotUtils.getPageById()`, etc.).
    Available globals: `penpot`, `penpotUtils`, `storage`, `console`.
  - `export-png` routes to the `export_shape` MCP tool (params `shapeId`,
    `format=png|svg`, **absolute** `filePath`). Penpot writes the file
    directly to disk — no local base64 decode, no HTTP bypass
    (unlike Frame0).
- **`wireframes.penpot_export_dir`** (new, config schema) — default
  directory for Penpot exports. Must be absolute (Penpot MCP
  constraint). Runtime default: `{project_root}/.claude/product/features/{feature_id}/wireframes/`.
- **Unified shape schema** between frame0 and penpot for `add-shapes`:
  `{type:"text|rect|ellipse", name, x, y, width, height, text, fill}`. Each
  helper normalises to its native SDK.
- **`skills/wireframe/step-00-init.md`** — resolves `wf_platform` (frame0 |
  penpot | none) and persists it in the skill state. Step-02 reads the
  matching helper.
- **`skills/wireframe/step-02-design.md`** — flow made platform-agnostic
  (helper/export routing table at the top, per-platform examples for
  `export-png`).
- **Tests**: 60 new `tests/test-penpot-helper.sh` tests (per-action arg
  validation, MCP descriptor shape for `execute_code`/`export_shape`,
  JS construction for add-shapes, dry-run vs read-actions, format enum
  png|svg, relative-path rejection, config-driven format default). 60/60
  passing. frame0 tests unchanged: still 97/97 OK.

### Changed — Wireframes export bypasses MCP via Frame0 HTTP API (breaking)

- **Why**: Frame0 MCP `export_page_as_image` returns the PNG in an
  `image` content block (base64 rendered visually by the Claude
  Code harness, never exposed as text → impossible to pipe to a script). The
  previous flow (`export-page` MCP → `save-export` base64) couldn't
  work from the harness.
- **`frame0-helper.sh export-png`** (new) — **local-only** action
  (never emits an MCP descriptor). Direct POST to the Frame0 desktop HTTP API
  (`http://localhost:<api-port>/execute_command`, `file:export-image`
  command); decodes the response `.data` base64, writes the
  file named per `--output-path` (= `feature_slug-screen_id-state.png`
  from the `/wireframe` skill). Args: `--page-id`, `--output-path`,
  optional `--format=png|jpeg|webp`, `--api-port=N`. Exit 0 success
  (`{written:true, bytes:N, mime, api_base}`), 1 if Frame0 desktop
  unreachable / API returns `success:false` / decode fails, 2 invalid
  args.
- **`wireframes.frame0_api_port`** (new, config schema) — Frame0 desktop
  HTTP API port. Default `58320` (= Frame0 default). Override only if
  Frame0 is launched with `--api-port=N`. The `wireframes.export_scale`
  sub-key is ignored by `export-png` (the Frame0 HTTP API has no scale
  parameter).
- **`frame0-helper.sh export-page`** — still present but **deprecated**
  for use from the Claude Code harness (header + usage note it).
  Kept for library/manual use.
- **`frame0-helper.sh save-export`** — still present (useful to decode
  arbitrary base64). Described as a general tool, no longer as a step of
  the `/wireframe` pipeline.
- **`skills/wireframe/step-02-design.md`** — steps 3+4 merged into a
  single `export-png` step. `## Dry-run` block updated
  (`export-png --dry-run` returns `{written:false}` without an HTTP hit).
- **Tests**: 14 new `export-png` tests (arg validation, format enum
  png|jpeg|webp, port validation, dry-run, mock success/error/missing-data,
  HTTP unreachable, config-port resolution, never an MCP descriptor). Mock
  via `$SNAP_FRAME0_MOCK_RESPONSE_FILE` (hidden test stub). 97/97 passing.

### Removed — Wireframes export source dir

- **`wireframes.export_source_dir`** (config schema) — removed. The premise
  (Frame0 writes to a single OS folder like `~/Downloads`) was wrong:
  Frame0 returns base64 via MCP, and the PNG now arrives directly
  on disk via `export-png`. No more `mv` from Downloads.
- **`frame0-helper.sh move-export`** — removed.
- Default-fill `wireframes.export_source_dir = "~/Downloads"` removed from
  `load-config.sh`.

### Changed — Plugin agents namespacing (breaking)

- **`snap-` prefix on all bundled plugin agents** to avoid collisions
  with the user project's `.claude/agents/`. Claude Code gives priority
  to project agents over plugin agents when names collide — without a
  prefix, a project `developer.md` or `code-reviewer-technical.md` agent
  would silently override the bundled one.
  - `agents/developer.md` → `agents/snap-developer.md`
  - `agents/code-reviewer-technical.md` → `agents/snap-code-reviewer-technical.md`
  - `agents/code-reviewer-functional.md` → `agents/snap-code-reviewer-functional.md`
  - `agents/code-reviewer-security.md` → `agents/snap-code-reviewer-security.md`
  - `agents/code-reviewer-qa.md` → `agents/snap-code-reviewer-qa.md`
  - Frontmatter `name:` aligned with the new file name.
- Refs updated in `skills/develop/` (step-00-init, step-02-prepare,
  step-03a-standalone) and `skills/qa/` (step-02-interpret, step-03-fix,
  step-04-retrigger). Note: `step-04-retrigger` was using pre-existing
  incorrect names (`reviewer-technical` instead of
  `code-reviewer-technical`) — fixed in passing.
- Docs updated: `docs/skills/develop.md`, `docs/structure.md`,
  `docs/plugin.md`, `docs/diagram.md`, `docs/roadmap.md`,
  `_shared/templates/docs-defaults/wireframes-gallery.md`.
- **User override**: a project that wants to override a plugin agent
  can create `.claude/agents/snap-<name>.md` (the project > plugin
  priority still applies on the prefixed name).

### Added — Templates customization

- **Customisable templates system** — `templates` section in
  `snapship.config.json` allows per-category override without touching the
  plugin (see `docs/templates.md`).
  - Schemas: `templates.tickets.{user_story,bug,epic}`,
    `templates.pr`, `templates.review_thread`, `templates.aggregated_feedback`
    (all `string|null`, default `null` → bundled).
  - Relative override → resolved from project root; absolute → as-is.
  - Override pointing to a missing file → `resolve-template.sh` exit 2
    (explicit failure, no silent fallback).
- `_shared/resolve-template.sh` — single resolution helper
  (kind=ticket|pr|review-thread|aggregated-feedback). User override > bundled.
  Exit 0 success | 1 invalid args | 2 file not found.
- `_shared/templates/` — **breaking** reorganisation (old paths removed):
  - `tickets/{user-story,bug,epic}/{github,gitlab,jira}.md` (9 templates,
    type × platform matrix)
  - `pr/{github,gitlab,default}.md`
  - `review-thread/{github,gitlab,jira}.md`
  - `aggregated-feedback.md` (internal fix-loop blob)
- `tickets-adapter.sh comment-pr` — new action to post a comment
  on a PR/MR (github via `gh pr comment`, gitlab via `glab mr note`). Args
  `--pr-id` + (`--comment` | `--body-file=PATH`). JIRA returns
  `{ok:false, error:"not_supported"}` exit 1 (no PR concept).
- `/ticket step-03-enrich` — heuristic ticket type classification
  (`user-story` by default, `bug` if keywords/scope match, `epic` if
  aggregating ≥3 child stories). Persisted on each story for pickup by step-04-format.
- `/ticket step-04-format` — per-story template resolution via
  `resolve-template.sh --kind=ticket --type=$story_type --platform=$platform`.
- `/develop step-04-sync` — section C "Post review thread (best-effort)":
  rendered via resolved `templates.review_thread` + posted via `comment-pr`.
- `/develop step-03a-standalone` — `aggregated_feedback` (dev fix-loop
  injection) rendered via resolved `templates.aggregated_feedback`.
- Tests:
  - `tests/test-resolve-template.sh` (25 assertions, 7 sections — args,
    bundled fallback × kinds, override ticket/pr/review-thread/agg, absolute
    path, missing file, null override).
  - `test-load-config.sh` extension ([13]-[15] templates defaults injection +
    user override preserved + schema rejection).
  - `test-tickets-adapter.sh` extension ([29]-[36] comment-pr dry-run, github
    via mock gh `pr comment`, gitlab via mock glab `mr note`, jira
    not_supported, missing pr-id / comment / body-file, no MCP descriptor
    leak).
  - Fixtures `tests/fixtures/valid/templates/` (5 custom templates),
    `tests/fixtures/invalid/config/bad-templates.json` (schema rejection).

### Removed — Templates customization (breaking)

- `repository.pr_template_path` field removed (replaced by `templates.pr`).
- `documentation.templates.prd_global` /
  `documentation.page_naming.prd_global` fields removed (aligned with the v0.2 removal of
  the `prd-global.md` template).
- Old flat templates `_shared/templates/ticket-{platform}.md` and
  `_shared/templates/pr-default.md` removed (replaced by the hierarchical
  layout `tickets/{type}/{platform}.md` and `pr/{platform}.md`).

### Added (v0.2 — breaking)

- **Doc architecture refactor** — PRD = immutable archive, functional doc = living source (see `docs/docs-architecture.md`).
  - PRD path: `{prd_root}/{YYYY}/{MM-YYYY}/{NN-feature}` (frozen post-ship, domain tags).
  - Functional doc: `{functional_root}/{domain}/{journey}` tree (incremental post-QA update).
- `/snap:doc-import` skill — bootstrap of an existing project: import legacy AFFiNE/Notion doc, `lookup-or-create-page` classification `{domain}/{journey}`, hydrate `domains.json`. 6 steps (init/discover/classify/normalize/publish/finish), ephemeral `.doc-import-cache/` cache.
- `/snap:doc-update` skill — propagates post-QA state to impacted functional pages. Modes `diff` (patch impacted sections) or `rewrite` (full regeneration, auto override if page empty). 5 steps (init/collect/update/publish/finish), AI prompts "describe end state, never reference PRD/tickets/git". Auto-trigger via `SNAP_NEXT_SKILL=` post-QA.
- `domains.schema.json` + `_shared/domains-state.sh` — persistent CRUD on `.claude/product/domains.json` (ID source of truth for idempotent `lookup-or-create`). Subcommands: init, add-domain, add-journey, get-domain, get-journey, list-domains, list-journeys, has-domain, has-journey, validate (ajv).
- `docs-adapter.sh` — 5 new idempotent write actions: `lookup-page`, `lookup-or-create-page`, `update-page-content`, `set-page-tags`, `create-page-tree`. MCP descriptor emission (exit 10); `--dry-run` short-circuits writes only.
- `/snap:define` step-05-publish — pushes the PRD archive (`{YYYY}/{MM-YYYY}/{NN-feature}` via `create-page-tree` + `apply-template`) AND guarantees `lookup-or-create-page` for each impacted `{domain}/{journey}`. Updates `domains.json`.
- `/snap:qa` step-05-finish — rollup `feature.state → qa-validated` when all tickets validated (jq mutation + ajv-validate post). Auto-triggers `/snap:doc-update` via `SNAP_NEXT_SKILL=doc-update --feature=${id} -a` if `documentation.auto_update_on_qa_success: true` (gated by `--no-doc-update` flag).
- Config additions: `documentation.paths.{functional_root,prd_root}`, `documentation.auto_update_mode` (`diff|rewrite`), `documentation.auto_update_on_qa_success` (bool). Defaults injected via `load-config.sh` (deep-merge).
- v0.2 fixtures: `tests/fixtures/valid/meta/{full,v02-defined}.json`, `valid/domains/{empty,full}.json`, `invalid/meta/{bad-domain-slug,legacy-affine-field}.json`, `invalid/domains/{missing-page-id,journey-missing-page-id}.json`.
- Tests: `tests/test-domains-state.sh` (22 assertions, 8 sections — add-domain idempotence preserves journeys, ajv validate). `test-docs-adapter.sh` extension (+ assertions [25]-[33] covering 5 v0.2 actions + dry-run write-only). `test-load-config.sh` extension ([10]-[12] paths defaults injection + override preserved including `auto_update_on_qa_success: false`). `validate-schemas.sh` extends to `domains/`.

### Changed (v0.2 — breaking)

- `meta.json` — schema breaking: drop `affine_page_id`, `affine_url`, `affine_wireframes_page_id`. Adds `domains: [string]`, `impacted_journeys: [{domain, journey_slug}]`, `prd: {page_id, url, path}`. `additionalProperties: false` now rejects the old fields.
- `/snap:ticket` step-01-load — reads `prd.page_id` / `prd.url` (instead of the legacy `affine_*`).
- Doc templates — `prd-feature.md` extended (full change-request variables: `feature_status`, `target_release`, `solution_overview`, `in_scope`/`out_of_scope`, `acceptance_criteria`, `user_segments`, `edge_cases`, `error_states`, `wireframes`, `tickets`, `open_questions` blocks).

### Removed (v0.2 — breaking)

- `prd-global.md` template removed — the "global PRD" is replaced by domain pages generated idempotently via `lookup-or-create-page` (`/snap:doc-import` or `/snap:define` publish).
- `meta.json.affine_*` fields (see Changed). No migration — v0.1 = dogfood pilot only.

### Fixed

- `load-config.sh` — deep-merge defaults bug: `// null` treated `false` as null, overwriting an explicit user override (`auto_update_on_qa_success: false` reverted to `true`). Fix: `if (.documentation | has("key")) | not then` (pattern aligned with the `paths` block). Test `test-load-config 12.4` covers the regression.

### Added

- Plugin manifest at `.claude-plugin/plugin.json` (Claude Code schema-compliant).
- Root `.mcp.json` bundles the `code-review-graph` MCP — auto-starts when plugin enabled.
- `NOTICE` documenting community MCP attributions (code-review-graph, affine-mcp-server, frame0-mcp-server, playwright-mcp).
- `/snap:init` skill: workspace bootstrap (config wizard + `.claude/product/` scaffold). MCP/git detection, AskUserQuestion drive, autonomous mode (`-a`), `--force` overwrite.
- Complete `/qa` skill: 6-step pipeline (init→collect→interpret→fix→retrigger→finish), regression scope=impacted via code-review-graph (tests-only fallback), Playwright vs Frame0 PNG wireframe diff, code-reviewer-qa agent, bounded dev↔qa cycle, opt-in retrigger of the 3 /develop reviewers.
- Complete `/develop` skill: standalone + loop session/daemon, 3 parallel reviewers (technical/functional/security), atomic commits, fail_strategy (next-ticket/stop/retry+fallback).
- Complete `/wireframe` skill: UI ticket filter, multi-screen Frame0 generation, AFFiNE gallery embed.
- Complete `/ticket` skill: PRD → ticket decomposition, explore-codebase enrichment, platform adapter push (github/gitlab/jira).
- Complete `/define` skill: initial setup wizard, interactive PRD brainstorm, AFFiNE storage.
- 4 reviewer agents: technical, functional, security, qa.
- E2E tests: define, ticket, wireframe, develop, qa (135 deterministic checks).

### Changed

- `tickets.json` schema extended for the /qa cycle: status enum + `qa-validated`, `acceptance_criteria.ac_id`, `qa_cycles_used`, `qa_last_severity`, `qa_last_flaky_verdict`, `qa_blocked`, `qa_retriggered`, `qa_retrigger_severity`, `qa_retrigger_verdicts`, `updated_at`.
- `/define` no longer creates `snapship.config.json` — responsibility moved to `/snap:init`. All skills (define/ticket/wireframe/develop/qa) exit early with a pointer to `/snap:init` if config is missing.
- `setup-config.sh --write` now generates `$schema` with the raw github URL (portable cross-install) instead of a plugin-relative path (broken once the plugin is installed outside the repo).

### Removed

- Legacy root `plugin.json` replaced by `.claude-plugin/plugin.json`.
- Invalid custom fields (`skills_path`, `agents_path`, `shared_scripts_path`, `schemas_path`, `templates_path`, `commands` array of objects, `mcp_servers`) — not supported by the CC plugin schema.

## [0.1.0] — TBD

First pre-marketplace scaffold. Target: internal validation on pilot project (Phase 8 dogfooding) before publication to the `bryanberger/claude-plugins` marketplace.
