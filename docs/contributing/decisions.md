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
| AFFiNE workspace      | 1 per code project, mapped via `snap.config.json` (`documentation.workspace`)                                                    |
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
| `/develop`            | Standalone (1 ticket = 1 dev/review cycle) + `--loop=session` (epic/feature)                                                        |
| Chaining              | Manual (suggestion at end of skill)                                                                                                 |
| Tickets sync          | Local draft → batch review → push                                                                                                   |
| Config                | `snap.config.json` at project root (extends bundled defaults)                                                                   |
| Auth                  | None in config — MCP/CLI handle it (gh auth, glab auth, $AFFINE_API_TOKEN)                                                          |
| Config sections       | `repository`, `tickets`, `documentation`, `wireframes`, `testing`, `naming`, `ai`, `develop`, `qa`, `defaults` |

## Design decisions

### Config bootstrap: dedicated `/snap:init` skill

**Choice:** dedicated `/snap:init` skill (steps `step-00-detect.md` + `step-01-write.md`) handles `snap.config.json` creation. All other skills (define/ticket/wireframe/develop/qa) exit early with `ERROR: snap.config.json not found. Run /snap:init first.` if config missing.

**Why:** separation of concerns, loud fail-fast > silent fallback, explicit init (1× per project).

**How to apply:** adding a new skill = add the guard `[ -f "$PWD/snap.config.json" ] || exit 1` at the start of step-00.

### Config `$schema`: GitHub raw URL

**Choice:** GitHub raw URL `https://raw.githubusercontent.com/BryanBerger98/snapship-plugin/main/skills/_shared/schemas/config.schema.json` (resolved by any IDE).

**Why:** cross-install portability — once installed via marketplace the schema file lives in the CC cache, not in the project, so a relative path would break IDE validation. Runtime `load-config.sh` always reads the schema from the plugin bundle (not via the `$schema` field), so ajv validation is unaffected.

### story_id_pattern

**Choice:** `story_id` always `NN-kebab` (decoupled from tickets). `ticket_id` separate, used only in `branch_pattern`/`commit_pattern`.

**Why:** simple, platform-independent. Decouples feature ↔ tickets (a feature is created before tickets exist).

### JIRA-only fields

**Choice:** nest JIRA-only fields (`project_key`, `workflow_states`, `transitions`, `epic_link_field`, `estimation_field`) under `tickets.jira.*`. Stderr warning if `platform != "jira"` AND `tickets.jira.*` set.

### Plugin distribution

**Choice:** plugin packaged via `.claude-plugin/plugin.json` (official CC schema). Install via CC marketplace or manual clone → official paths `~/.claude/skills/` + `~/.claude/agents/` (or project `.claude/`). No custom symlink.

### Wireframe diff (QA)

**Choice:** structural-diff (Frame0 MCP shapes ↔ Playwright DOM) rather than pixel-diff. Structure comparison (button/input/section counts match, labels present).

### Documentation: PRD archive vs living functional docs

**Choice:** two distinct page types:
- **PRD / Change request** — immutable archive of a change. Path: `{prd_root}/{YYYY}/{MM-YYYY}/{NN-feature}`. Tags = impacted domains. Frozen post-ship.
- **Functional doc** — living spec, hierarchy `{functional_root}/{domain}/{user journey}`. Updated on each ship via `/snap:doc-update`.

**Why:** PRD = "what we're going to change" (forward-looking, stale post-ship). Functional doc = "what the product does today" (current source of truth). Mixing them pollutes both uses.

**How to apply:** full spec in `docs/usage/concepts.md`.

### Functional doc: domain → journey structure

**Choice:** 2-level hierarchy:
- Domain page (`auth`, `dashboard`) = overview + links to journeys
- User journey page (`Login Flow`, `Signup Flow`) = detailed living spec

**No modification log on domain page** — would cause exponential bloat on long-running projects. History = via the PRD pages themselves (filterable in AFFiNE by tag + date).

**No direct journey → PRD link** — journey stays a clean spec, PRD = external archive.

### Existing doc bootstrap: `/snap:doc-import` skill

**Choice:** `/snap:doc-import` skill reads existing AFFiNE pages → AI proposes domain/journey split → user confirms → restructures per strategy:
- `synthesize` (default): AI consolidates N source pages → 1 journey doc
- `copy`: duplicates to snap path, archives originals
- `move`: relocates source pages to snap path

**Why:** existing docs are common. Without automated bootstrap, plugin unusable on existing projects.

**How to apply:** skill separated from `/snap:define` (one-shot bootstrap vs dev cycle).

### Auto-update docs post-ship

**Choice:** standalone `/snap:doc-update` skill, triggered:
- Auto post-`/snap:qa` if `documentation.auto_update_on_qa_success: true`
- Manual `/snap:doc-update --feature=NN`

Configurable update mode: `diff` (default — patch impacted sections) or `rewrite` (regenerate full journey doc). PRD never touched by this skill.

### Nested per-platform config

**Choice:** nest each platform-specific block under `wireframes.{frame0,penpot,figma}` + parallel `design.{penpot,figma}` section. `additionalProperties: false` at the block level enforces strict schemas.

**Why:** scalability (adding a platform = one sub-block, not N top-level keys), schema correctness (`additionalProperties:false` excludes noise), `/wireframe` ↔ `/design` parity (same Penpot/Figma blocks).

### `/design` scope — mockups only

**Choice:** `/design` does **one thing only** — hi-fi mockups. Takes a `<ticket-id|story-id>` as input (like `/develop` and `/qa`) and builds mockups based on what the ticket requires. `/design figma` uses the **same** `figma-helper.sh` and the **same** Desktop Bridge plugin as `/wireframe figma`.

**Why:** one skill = one responsibility. Design system management belongs to a dedicated tool, not a mode grafted onto the mockup skill. `/design` and `/wireframe` share exactly the same Figma surface — a single helper to maintain.

**Note:** the **Desktop Bridge plugin** (Figma plugin, `figma-console-mcp` WebSocket channel) is required for `/design figma` and `/wireframe figma`.

**How to apply:** `design.figma` → `figma-helper.sh` helper + direct `figma_execute`, identical to `wireframes.figma`. Optional DS reading via `design.mode_defaults.design_system_source` (`none|file|auto`) — the DS is **read** for reference, never written.

### Repo-native templates `.github` / `.gitlab`

**Choice:** intermediate **repo-native** layer between config override and bundled. Resolution order: `config override > repo-native > bundled`. `detect-repo-templates.sh` helper scans GitHub/GitLab conventions (markdown only, YAML forms ignored). `resolve-template.sh` emits JSON `{path, source, render_mode}`; `render_mode` is `mustache` (config/bundled, `{{var}}` placeholders) or `scaffold` (repo-native, markdown skeleton filled section by section). Layer enabled by `templates.use_repo_native` (default `true`).

**Why:** reusing what the team already defined = output consistent with the repo, zero config for the common case. The `scaffold` mode avoids forcing the bundled structure on a house template: we keep the repo's section order and checklists. An explicit config override always wins — the user keeps control. JIRA has no file-based repo-native convention (no `.jira/`, no file-based templates in the REST API) → stays on config/bundled. `review-thread` and `aggregated-feedback` are internal snap artifacts, with no repo-native equivalent.

**Scoping:** (1) precedence `config > repo-native > bundled`; (2) `review-thread` keeps the bundled snap template (no host convention for a review cycle comment); (3) markdown only — if a repo only has YAML issue forms, we fall back to bundled (no form schema parser).

**How to apply:** nothing to do — `use_repo_native` defaults to `true`. To disable: `templates.use_repo_native: false`. To force a specific template: `templates.tickets.*` / `templates.pr` (explicit override, priority).

### Slug vs title

**Choice:** AFFiNE page = human title ("Login Flow"). Internal cache `_taxonomy.json` = kebab slug (`login-flow`) for mapping. User enters title, slug auto-generated (override possible).

### Applied CC optimizations

1. **Parallel agent tool** — `/develop` Phase 2 review cycle spawns 3 reviewers via 1 message N Agent calls (= native parallel CC, context isolated per fork)
2. **Opt-in SessionStart hook** — pre-load config via `session-start-hook.sh.tpl` template + user `settings.json` entry
3. **`/usage` + `/cost`** — recommended at step-finish for consumption monitoring
4. **NDJSON telemetry** — `_shared/telemetry.log` append-only with 10MB rotation
5. **Global `--dry-run`** — preview write ops without touching prod (combinable with `-a`)

## Validation decisions

1. **Build order:** `/define` → `/ticket` → `/wireframe` → `/develop` → `/qa`
2. **Skills/agents location:** packaged via `.claude-plugin/plugin.json` (official CC schema). Install via CC marketplace or manual clone → official paths `~/.claude/skills/` + `~/.claude/agents/` (or project `.claude/`). No custom symlink.
3. **docs-defaults templates:** bundled in `_shared/templates/docs-defaults/` (opt-in push via setup)

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

## v1.2.0 — ticket hierarchy redesign (YYYY-MM-DD)

Reworks the ticket model around an explicit Epic / User Story / Task / Bug taxonomy, makes the tracker the sole source of truth for tickets (platform-first, cache éphémère intra-run), and renames the product surface from `snapship` to `snap` (config file, env file, plugin manifest). Scope also covers the `feature_id` → `story_id` rename, worktree resolution simplification, and the removal of `subtask_root`.

### Actioned decisions (16)

- **Decision 1 — No offline mode** — every flow assumes connectivity (LLM + tracker), removing the offline guarantee in exchange for a simpler architecture.
- **Decision 2 — Ephemeral ticket cache** — tickets live in `.snap/.runtime/<subject-id>/tickets.json` for the duration of one skill run, replacing the persistent `.snap/tickets/{feature_id}.json`.
- **Decision 3 — No local cache for Epics / Milestones / Versions** — platform-first lookup live each time; the tracker list is the single source of truth and `/fetch` no longer syncs these objects.
- **Decision 4 — Feature = User Story** — a "feature" maps exactly to one deliverable User Story; vocabulary aligned with Agile and `feature_id` renamed to `story_id`.
- **Decision 5 — Epic is project-management only** — `story_type=epic` never produces a branch, commit, or `/develop`/`/qa` run; schema forbids `branch_name`/`commit_sha` on epics.
- **Decision 6 — Remote state is authoritative** — local state loses normative value; `/develop` accepts any existing tracker ticket (US, Bug, Task) without local state-machine prerequisite.
- **Decision 7 — `/ticket --standalone`** — allows ticket creation without a parent feature/story or PRD, for isolated technical work (e.g. "upgrade Node 20").
- **Decision 7b — Strict hierarchical push** — a child ticket cannot be pushed if its parent is not already on the tracker; step-05 orders parents first, blocks children with an explicit message otherwise.
- **Decision 7c — `/develop` ignores the PRD** — the skill reads only the ticket (and any references it points to), decoupling `meta.json` from ticket lifecycle so `/develop --ticket=<platform_id>` works on any tracker ticket.
- **Decision 7d — Big-bang `feature_id` → `story_id` rename** — no retro-compatibility alias; migration shipped in one coherent commit and handled downstream by `/upgrade`.
- **Decision 7e — Cache purge immediate, scoped by subject** — `.snap/.runtime/<subject-id>/` is purged on skill exit (success or failure); distinct subject-ids keep concurrent runs isolated.
- **Decision 7f — `target_version` explicit, no inheritance** — user sets the target version per ticket when relevant; empty means no target, no silent propagation.
- **Decision 8 — `/define` is multi-mode** — single skill with internal routing (vision / journey / story / refinement), no split into `/define-vision` or `/define-journey`.
- **Decision 9 — Single schema constraint: epic forbids branch/commit** — `commit_type` stays free and uncoupled from `story_type`; one allOf rule keeps validation usable in continuous mode during `/ticket`.
- **Decision 10 — LLM clustering heuristic in auto mode** — the agent auto-groups stories under Epics and proposes Task ↔ US hierarchy with a warn; interactive mode keeps explicit user concertation.
- **Decision 11 — `subtask_root` removed** — worktree strategy is fixed (Task under US shares the US worktree; Task standalone or under Epic gets its own); schema keeps only `path`, `default_root`, `destroy`.
- **Decision 12 — `naming.branch_pattern` simplified** — global default becomes `{type}/{ticket_id}`, `{slug}` dropped; breaking change migrated via `/upgrade`.
- **Decision 13 — `naming.commit_pattern` token rename** — `{type}` becomes `{commit_type}`; breaking template change, documented upgrade.
- **Decision 14 — GitHub `task` issue_type mapping** — `tickets.github.issue_types.task` added for symmetry with other story_types; adapter routes `story_type=task` to the configured GH Issue Type.
- **Decision 15 — Bug parent matrix** — Bug can have Task children, Bug-as-parent-of-Bug forbidden; parent-child matrix updated accordingly.
- **Decision 16 — Plugin rename `snapship` → `snap`** — big-bang user-facing rename: `snapship.config.json` → `snap.config.json`, `.env.snapship` → `.env.snap`, plugin manifest `name` → `snap`. Git repo keeps `snapship-plugin`, product identity is `snap`. Migration via `/upgrade`.

### Additional v1.2 subjects

- **Tracker version mapping — degenerate cases** — `target_version` is a single explicit ticket field, mapped per platform via adapter capability (`supports_version`). GitHub Releases + Git tags, GitLab Releases, Jira Fix Version, Linear Releases; when `supports_version=false` the value is silently ignored with a one-shot warn.
- **Epic post-merge auto-close** — `/develop` post-merge step calls `close_epic_if_all_children_done(epic_id)` through the adapter (Jira transition, Linear state, GitLab API, GH marker comment + manual). Capability-gated and opt-out via `--no-epic-close`.
- **Subagent orchestration constraint** — subagents cannot nest, so the orchestrator (parent skill) centralises any digest/summary spawn instead of letting a child agent spawn its own; keeps fan-out predictable and bounded.
- **Haiku for classifier + digest** — extraction-only jobs (ticket classification, digest summarisation) target Haiku to optimise cost and latency without quality loss on these narrow tasks.
- **One-ticket-per-`/develop`-call** — invocation pattern is single-ticket; multi-ticket loops are dropped from `/develop` in favour of explicit external orchestration (composable, easier to resume, no implicit batching).

### Historical reference

Detailed plans archived at `.claude/plan/ticket-hierarchy-redesign/` until Phase J cleanup. After cleanup, original plans accessible via git history at tag `v1.2.0`.
