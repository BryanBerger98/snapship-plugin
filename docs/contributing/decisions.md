# Decisions

## Validated decisions (config workflow)

| Decision              | Choice                                                                                                                              |
| --------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| Architecture          | 5 independent chainable skills, inline workflow                                                                                     |
| Slash commands        | `/define`, `/ticket`, `/wireframe`, `/develop`, `/qa`                                                                               |
| Ticket platforms      | Hybrid MCP-first → CLI fallback (gh/glab/jira)                                                                                      |
| Frame0                | MCP `frame0-mcp-server` (28 tools available)                                                                                        |
| AFFiNE                | MCP `affine-mcp-server` (DAWNCR0W, 84 tools) — primary product docs source                                                          |
| Docs templates        | Native AFFiNE template pages (UI), referenced by template_id                                                                        |
| Generated AFFiNE pages | Global PRD, feature PRD, feature wireframes gallery                                                                                |
| AFFiNE workspace      | 1 per code project, mapped via `snapship.config.json` (`documentation.workspace`)                                                    |
| PRD source of truth   | AFFiNE (primary) — minimal local                                                                                                    |
| Tickets source of truth | Primary platform, local cache                                                                                                     |
| Local storage         | `.snap/` minimal (cache + progress + meta)                                                                                          |
| PRD                   | Global + mini-PRD per feature (on AFFiNE)                                                                                           |
| Wireframes            | Per feature, multi-screen (Frame0 + AFFiNE gallery)                                                                                 |
| Ticket format         | Adaptive per platform                                                                                                               |
| Language              | French                                                                                                                              |
| Mode                  | Interactive by default, `-a` autonomous                                                                                             |
| Resume                | `-r` everywhere                                                                                                                     |
| Existing project      | Auto-detect + discovery                                                                                                             |
| `/develop`            | Standalone (1 ticket = 1 dev/review cycle) + `--loop=session\|daemon` (epic/feature)                                                |
| Chaining              | Manual (suggestion at end of skill)                                                                                                 |
| Tickets sync          | Local draft → batch review → push                                                                                                   |
| Config                | `snapship.config.json` at project root (extends bundled defaults)                                                                   |
| Auth                  | None in config — MCP/CLI handle it (gh auth, glab auth, $AFFINE_API_TOKEN)                                                          |
| Config sections       | `repository`, `tickets`, `documentation`, `wireframes`, `testing`, `naming`, `ai`, `develop`, `qa`, `lifecycle_scripts`, `defaults` |

## Design decisions (issue resolution history)

### Config bootstrap: dedicated `/snap:init` skill

**Issue:** `/define` carried both `snapship.config.json` creation and product definition. Consequences: overloaded step-00, silent failure when `load-config.sh` treated missing config as `{}` (no fail-fast), coupling between init and PRD workflow entry.

**Choice:** extracted into dedicated `/snap:init` skill (steps `step-00-detect.md` + `step-01-write.md`). All other skills (define/ticket/wireframe/develop/qa) exit early with `ERROR: snapship.config.json not found. Run /snap:init first.` if config missing.

**Why:** separation of concerns, loud fail-fast > silent fallback, explicit init (1× per project).

**How to apply:** adding a new skill = add the guard `[ -f "$PWD/snapship.config.json" ] || exit 1` at the start of step-00.

### Config `$schema`: GitHub raw URL

**Issue:** `setup-config.sh --write` injected `"$schema": "./skills/_shared/schemas/config.schema.json"` (path relative to project root). Once the plugin is installed via marketplace, the schema file lives in the CC cache, not in the project → IDE schema validation broken.

**Choice:** GitHub raw URL `https://raw.githubusercontent.com/BryanBerger98/snapship-plugin/main/skills/_shared/schemas/config.schema.json` (resolved by any IDE once the repo is public).

**Why:** cross-install portability. Runtime `load-config.sh` always reads the schema from the plugin bundle (not via the `$schema` field), so ajv validation is unaffected.

### feature_id_pattern

**Issue:** `/define` creates a feature before tickets exist → pattern `{ticket_id}-{feature_slug}` impossible.

**Choice:** **Option B** — `feature_id` always `NN-kebab` (decoupled). `ticket_id` separate, used only in `branch_pattern`/`commit_pattern`.

**Why:** simple, platform-independent. Decouples feature ↔ tickets.

### JIRA-only fields

**Issue:** JIRA-only fields `project_key`, `workflow_states`, `transitions`, `epic_link_field`, `estimation_field` mixed at top-level `tickets`.

**Choice:** nest under `tickets.jira.*`. Stderr warning if `platform != "jira"` AND `tickets.jira.*` set.

### `hooks` vs `lifecycle_scripts`

**Issue:** semantic collision with native Claude Code hooks (`SessionStart`, `PreToolUse`).

**Choice:** rename config key + script file:

- `config.hooks` → `config.lifecycle_scripts`
- `_shared/run-hook.sh` → `_shared/run-lifecycle-script.sh`
- Flag `--no-fail-hooks` → `--no-fail-lifecycle`

**Why:** clarity workflow vs native CC.

### Plugin v1 distribution

**Issue:** unofficial `~/.agents/` symlink convention.

**Choice:** plugin v1 packaged via `.claude-plugin/plugin.json` (official CC schema). Install via CC marketplace or manual clone → official paths `~/.claude/skills/` + `~/.claude/agents/` (or project `.claude/`). No custom symlink.

### `merge_method` config

**Issue:** `merge_method` field (squash/rebase/merge) unused in v1.

**Choice:** dropped. User merges PR manually after creation.

### Fixtures v1

**Choice:** skip fixtures in v1. No bundled examples directory.

### Wireframe diff (QA)

**Choice:** structural-diff (Frame0 MCP shapes ↔ Playwright DOM) rather than pixel-diff. Structure comparison (button/input/section counts match, labels present).

### Documentation: PRD archive vs living functional docs (v0.2)

**Issue:** v0.1 treats everything as flat AFFiNE pages — 1 global PRD + 1 PRD per feature. No separation between change intent (ephemeral PRD) and current product state (living functional docs). Page-to-page links broken in practice. No configurable path.

**Choice:** v0.2 redesign — two distinct page types:
- **PRD / Change request** — immutable archive of a change. Path: `{prd_root}/{YYYY}/{MM-YYYY}/{NN-feature}`. Tags = impacted domains. Frozen post-ship.
- **Functional doc** — living spec, hierarchy `{functional_root}/{domain}/{user journey}`. Updated on each ship via new skill `/snap:doc-update`.

**Why:** PRD = "what we're going to change" (forward-looking, stale post-ship). Functional doc = "what the product does today" (current source of truth). Mixing them pollutes both uses.

**How to apply:** full spec in `docs/usage/concepts.md`. Breaking change vs v0.1, no migration (pilot only).

### Functional doc: domain → journey structure

**Choice:** 2-level hierarchy:
- Domain page (`auth`, `dashboard`) = overview + links to journeys
- User journey page (`Login Flow`, `Signup Flow`) = detailed living spec

**No modification log on domain page** — would cause exponential bloat on long-running projects. History = via the PRD pages themselves (filterable in AFFiNE by tag + date).

**No direct journey → PRD link** — journey stays a clean spec, PRD = external archive.

### Legacy doc bootstrap: `/snap:doc-import` skill

**Issue:** an existing project with accumulated free/scattered AFFiNE docs doesn't follow the snap hierarchy. Manual bootstrap = major friction.

**Choice:** `/snap:doc-import` skill reads existing AFFiNE pages → AI proposes domain/journey split → user confirms → restructures per strategy:
- `synthesize` (default): AI consolidates N source pages → 1 journey doc
- `copy`: duplicates to snap path, archives originals
- `move`: relocates source pages to snap path

**Why:** legacy docs = common. Without automated bootstrap, plugin unusable on existing projects.

**How to apply:** skill separated from `/snap:define` (one-shot bootstrap vs dev cycle). NO v0.1 → v0.2 migration (pilot only). NO local-source equivalent (drops the originally proposed `doc-rebuild`).

### Auto-update docs post-ship

**Choice:** standalone `/snap:doc-update` skill, triggered:
- Auto post-`/snap:qa` if `documentation.auto_update_on_qa_success: true`
- Manual `/snap:doc-update --feature=NN`

Configurable update mode: `diff` (default — patch impacted sections) or `rewrite` (regenerate full journey doc). PRD never touched by this skill.

### Nested per-platform config (v0.5 — breaking)

**Issue:** v0.4 mixed platform-specific keys flat inside `wireframes` (`frame0_api_port`, `penpot_export_dir`, `penpot_file_id`, …). Non-scalable pattern: adding Figma would have continued the lateral inflation (`figma_file_key`, `figma_token_env`, …), and the schema couldn't express the coupling "this field only makes sense when platform=X".

**Choice:** nest each platform-specific block under `wireframes.{frame0,penpot,figma}` + create a parallel `design.{penpot,figma}` section. Bump 0.4 → 0.5.0, no compatibility shim (pilot plugin, consistent with v0.2 decision). `additionalProperties: false` at the block level rejects the old flat keys.

**Why:** scalability (adding a platform = one sub-block, not N top-level keys), schema correctness (`additionalProperties:false` excludes noise), `/wireframe` ↔ `/design` parity (same Penpot/Figma blocks).

**How to apply:** user migration via `scripts/migrate-config-v04-to-v05.sh` (one-shot jq, not bundled at runtime). Old → new mapping documented in `docs/usage/configuration.md` + `CHANGELOG.md` v0.5.0.

### `/design` reduced to mockups — Bridge CLI tooling removed (Unreleased — breaking)

**Issue:** v0.5–v0.6 loaded `/design` with four modes (`ds-extract`, `ds-init`, `ds-update`, `mockup`) and a separate CLI compiler (`bridge-ds`, repo `noemuch/bridge`) to manage the design system inside Figma. Wide surface, external Node.js dependency, auto-resolved modes risking clobber of Figma edits. Design systems are better managed outside the plugin.

**Choice:** `/design` now does **one thing only** — hi-fi mockups. Removed the `ds-extract` / `ds-init` / `ds-update` modes, the `bridge-ds` CLI and the `figma-bridge-helper.sh` helper, the `design-mode-resolver.sh`, the `design-system-defaults/` templates, and the config keys `design.extract` + `design.figma.{bridge_kb_path,bridge_transport}`. `/design` now takes a `<ticket-id|feature-id>` as input (like `/develop` and `/qa`) and builds mockups based on what the ticket requires. `/design figma` uses the **same** `figma-helper.sh` and the **same** Desktop Bridge plugin as `/wireframe figma`.

**Why:** one skill = one responsibility. DS (creation, update) belongs to a dedicated tool, not a mode grafted onto the mockup skill. Removing `bridge-ds` eliminates an external npm dependency and a clobber risk (auto re-run → push DS that overwrites Figma). `/design` and `/wireframe` now share exactly the same Figma surface — a single helper to maintain.

**Note:** the **Desktop Bridge plugin** (Figma plugin, `figma-console-mcp` WebSocket channel) remains required — it has no link with the removed `bridge-ds` CLI. Two distinct entities that shared the "Bridge" name.

**How to apply:** `design.figma` → `figma-helper.sh` helper + direct `figma_execute`, identical to `wireframes.figma`. Optional DS reading via `design.mode_defaults.design_system_source` (`none|file|auto`) — the DS is **read** for reference, never written. v0.5/v0.6 configs: remove `design.extract` and `design.figma.{bridge_kb_path,bridge_transport}` (rejected by `additionalProperties:false`).

### Repo-native templates `.github` / `.gitlab` (Unreleased)

**Issue:** `/ticket` and `/develop` always rendered their tickets/PRs from bundled templates (or an explicit config override). A project that already has its conventions in `.github/ISSUE_TEMPLATE/` or `.gitlab/merge_request_templates/` had its house style ignored — adoption friction, output that doesn't look like the rest of the repo.

**Choice:** add an intermediate **repo-native** layer between config override and bundled. Resolution order: `config override > repo-native > bundled`. New `detect-repo-templates.sh` helper scans GitHub/GitLab conventions (markdown only, YAML forms ignored). `resolve-template.sh` now emits JSON `{path, source, render_mode}`; `render_mode` is `mustache` (config/bundled, `{{var}}` placeholders) or `scaffold` (repo-native, markdown skeleton filled section by section). Layer enabled by `templates.use_repo_native` (default `true`).

**Why:** reusing what the team already defined = output consistent with the repo, zero config for the common case. The `scaffold` mode avoids forcing the bundled structure on a house template: we keep the repo's section order and checklists. An explicit config override always wins — the user keeps control. JIRA has no file-based repo-native convention (no `.jira/`, no file-based templates in the REST API) → stays on config/bundled. `review-thread` and `aggregated-feedback` are internal snap artifacts, with no repo-native equivalent.

**Scoping decisions:** (1) precedence `config > repo-native > bundled`; (2) `review-thread` keeps the bundled snap template (no host convention for a review cycle comment); (3) markdown only — if a repo only has YAML issue forms, we fall back to bundled (no form schema parser).

**How to apply:** nothing to do — `use_repo_native` defaults to `true`. To disable: `templates.use_repo_native: false`. To force a specific template: `templates.tickets.*` / `templates.pr` (explicit override, priority).

### Slug vs title

**Choice:** AFFiNE page = human title ("Login Flow"). Internal cache `_taxonomy.json` = kebab slug (`login-flow`) for mapping. User enters title, slug auto-generated (override possible).

### Applied CC optimizations

1. **Parallel agent tool** — `/develop` Phase 2 review cycle spawns 3 reviewers via 1 message N Agent calls (= native parallel CC, context isolated per fork)
2. **Opt-in SessionStart hook** — pre-load config via `session-start-hook.sh.tpl` template + user `settings.json` entry
3. **`/usage` + `/cost`** — recommended at step-finish for consumption monitoring
4. **NDJSON telemetry** — `_shared/telemetry.log` append-only with 10MB rotation
5. **Global `--dry-run`** — preview write ops without touching prod (combinable with `-a`)

## Validation decisions (pre-build)

1. **Plan validated** ✅
2. **Build order:** `/define` → `/ticket` → `/wireframe` → `/develop` → `/qa`
3. **Skills/agents location:** plugin v1 packaged via `.claude-plugin/plugin.json` (official CC schema). Install via CC marketplace or manual clone → official paths `~/.claude/skills/` + `~/.claude/agents/` (or project `.claude/`). No custom symlink.
4. **docs-defaults templates:** bundled in `_shared/templates/docs-defaults/` (opt-in push via setup)

## Drop list (not retained in v1)

- `epic_link_field`, `estimation_field`, `ci_provider`, `coverage_threshold` — misleading config
- `test_folder_name`, `test_files_pattern`, `storage.product_dir` — never read
- Mid-step hooks (only pre/post skill kept via `lifecycle_scripts`)
- `~/.agents/` symlink convention
- Skill-side PR auto-merge
- `merge_method` config field

## Inline patterns (no external dependency)

Autonomous workflow. Native patterns:

**Progressive workflow:**

- Step loading via `next_step` frontmatter (1 step = 1 MD file)
- State variables persisted between steps (`progress.json` + `manifest.json`)
- Save mode + templates + `_shared/` scripts
- Resume `-r {task-id}` with partial match
- Self-validation typecheck/lint/test post-execution

**UX & flags:**

- Flag system (lowercase enable, uppercase disable)
- AskUserQuestion at each key phase (with `ask-or-default.sh` wrapper for `-a` autonomous)
- Accept/Plan/Cancel menus on intermediate outputs
- Interactive brainstorm with parallel exploration

**Execution:**

- 1–10 parallel agents based on complexity
- Atomic stories 5–30 min (1 ticket = 1 atomic commit)
- Branch naming configurable via `naming.branch_pattern`
- Daemon loop = setup-only (generates script, user launches — never auto-launch)
