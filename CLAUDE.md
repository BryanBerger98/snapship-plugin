# CLAUDE.md — snapship-plugin

This repo **is** a Claude Code plugin. Six product skills (`define → ticket → wireframe → design → develop → qa`) plus three utility skills (`init`, `fetch`, `upgrade`, `doc-import`, `doc-update`) chain a one-line feature idea into a shipped, QA'd pull request. Pure Bash, no Node/Python runtime.

## Architecture mental model

**Remote platforms are sources of truth.** Local (`.snap/`) only pre-generates, validates, and stages before push. Helpers that touch remote state always go through the platform adapter (`docs-adapter.sh`, `tickets-adapter.sh`, `figma-helper.sh`, `frame0-helper.sh`, `penpot-helper.sh`).

A skill is a directory under `skills/<name>/`:

- `SKILL.md` — frontmatter + skill description (loaded by Claude Code).
- `steps/step-NN-<slug>.md` — one Markdown file per pipeline step (zero-padded, sequential). Each step is a self-contained prompt.
- Optional `templates/` for skill-specific scaffolding.

State machine on each feature manifest: `defined → ticketed → wireframed → designed → developed → qa-validated → shipped`. Each terminal step writes the transition.

`skills/_shared/` is the helper layer. Every skill calls into it:

- **Adapters** — `docs-adapter.sh` (AFFiNE/Notion), `tickets-adapter.sh` (GH/GL/JIRA/Linear), `figma-helper.sh`, `frame0-helper.sh`, `penpot-helper.sh`.
- **State** — `load-config.sh`, `load-env.sh`, `progress.sh` (start/step/finish/resume), `taxonomy-state.sh`, `define-state.sh`.
- **Detection** — `detect-codebase.sh`, `detect-platforms.sh`, `detect-repo-templates.sh`, `detect-test-commands.sh`, `check-mcp-required.sh`.
- **Sync** — `sync-push.sh` / `sync-fetch.sh` (write-through outbox, replay refs).
- **Schemas** — `skills/_shared/schemas/*.json` (Ajv-validated in CI).

`agents/` holds five `snap-`-prefixed subagents (`snap-developer`, `snap-code-reviewer-{technical,functional,security,qa}`). The `snap-` prefix prevents collision with downstream-project agents.

## Layout

```
snapship-plugin/
├── .claude-plugin/plugin.json        # CC manifest (entry point)
├── .mcp.json                          # bundled code-review-graph MCP
├── agents/                            # 5 snap-* agents
├── skills/
│   ├── init/ define/ ticket/ wireframe/ design/ develop/ qa/
│   ├── fetch/ upgrade/ doc-import/ doc-update/
│   └── _shared/                       # helpers, schemas, templates, migrations
├── tests/                             # custom bash assertion suite
├── docs/usage/  docs/contributing/    # split by audience
└── CHANGELOG.md  README.md  LICENSE  NOTICE
```

User-facing config lives at the **downstream project root**, not here: `snapship.config.json`, `.snap/manifests/`, `.snap/tickets/`, `.snap/progress.json`, `.env.snapship`. The plugin repo itself has no `.snap/`.

## Required runtime

- `bash` 4+, `jq`, `curl`, `git`. Plugin refuses to run without them.
- `code-review-graph` MCP — bundled in `.mcp.json` but binary installs separately via `pipx install code-review-graph`.
- Platform MCPs are optional and detected at runtime. Skills degrade gracefully (e.g. `/qa` falls back to `scope=tests-only` if `code-review-graph` is missing).

## Pre-commit checks (mandatory)

Run all four before every commit. Don't skip with `--no-verify`.

```bash
shellcheck -x skills/_shared/*.sh skills/**/*.sh tests/*.sh         # severity ≥ warning
bash tests/validate-schemas.sh && for f in tests/test-*.sh; do bash "$f" || exit 1; done
claude plugin validate .                                             # manifest schema
find . -name '*.json' -not -path './.code-review-graph/*' -exec jq empty {} \;  # JSON well-formed
```

`.github/workflows/validate.yml` is the canonical sequence — re-runs the same gates on push and PR.

## Conventions

- **Commits** — Conventional Commits with scope: `feat(scope): …`, `fix(scope): …`, `docs(scope): …`, `refactor(scope)!: …` (breaking). Co-Authored-By trailer when Claude wrote the patch.
- **Branches** — `feat/<slug>`, `fix/<slug>`, `docs/<slug>`, `refactor/<slug>`. Direct commits to `main` only for trivial fixes you'd accept in a PR.
- **Step files** — `step-NN-<kebab-slug>.md`, zero-padded, sequential. Sub-steps use a letter suffix (`step-03a-…`, `step-03b-…`).
- **Helpers** — platform adapters end in `-helper.sh` (Figma/Frame0/Penpot) or `-adapter.sh` (docs/tickets). State managers end in `-state.sh`.
- **Agents** — always `snap-` prefix.
- **Bash** — `set -euo pipefail` at the top, prefer `[[ ]]` over `[ ]`, quote variables, shellcheck-clean.
- **Schemas** — `additionalProperties: false` everywhere. Add a key → bump version + update fixtures + update CHANGELOG.

## Working in this repo

- Use `code-review-graph` MCP tools (`semantic_search_nodes`, `get_impact_radius`, `query_graph`, `detect_changes`) **before** Grep/Read/Glob. The graph is faster, cheaper, and gives structural context that file scanning misses.
- Editing a helper in `skills/_shared/` likely affects multiple skills — check impact radius before changing a signature.
- New shared helpers need a `tests/test-<name>.sh` companion. The suite expects parity.
- New skill steps need an entry in the parent `SKILL.md` and a progress.json terminal transition.
- Schema changes touch fixtures under `tests/fixtures/` — fail CI if forgotten.

## Tests on business logic — no mocks

Helpers that touch state or platforms (`progress.sh`, `taxonomy-state.sh`, `load-config.sh`, the adapters) are tested against **real** behaviour: real `jq` parses, real temp dirs, real file I/O. Don't replace a helper with a mock to "make tests pass." If the helper is hard to test, refactor the helper, not the test.

## Hard rules

- **Never `rm`.** Use `trash` for any deletion — reversible via system trash. The repo's helpers and tests already follow this; matching it is required.
- **Never commit secrets.** `.env.snapship` is gitignored on downstream projects; tokens for Figma/Notion/AFFiNE belong there, never inline in `snapship.config.json`.
- **Never skip pre-commit hooks** (`--no-verify`, `--no-gpg-sign`). If a hook fails, fix the cause.
- **Don't drift docs.** `docs/usage/` is for plugin users, `docs/contributing/` is for plugin developers. Don't mix audiences.

## Analysis / audit / planning requests

When the user asks for an **analysis**, an **audit**, or **task planning** (mots-clés FR/EN : `analyse`, `audit`, `planifie`, `plan`, `planning`, `cadrage`), **do not write code**. No `Edit`, no `Write` on source files, no shell mutations. Read-only exploration only (`code-review-graph` MCP, `Read`, `Grep`, `Glob`).

Deliverable goes to `.claude/plan/{task_name}/` (kebab-case slug derived from the request):

1. Create `.claude/plan/{task_name}/README.md` — synthesis of the analysis/audit/planning. Sections:
   - **Contexte** — what was asked, scope, assumptions.
   - **Constats** — findings from the codebase (cite file paths + line numbers).
   - **Risques / impacts** — blast radius, coupling, regressions to watch.
   - **Découpage en phases** — one phase per file to touch. For each phase:
     - `### Phase N — <relative/path/to/file>`
     - Objective (1 sentence, why this file).
     - Detailed checklist (`- [ ]` items) of every concrete change required in that file: functions to add/edit/remove, signatures, schema keys, tests to update, etc. Granular enough that another agent could execute the phase without re-deriving intent.
   - **Ordre d'exécution** — phase dependencies, suggested sequence.
   - **Critères de validation** — how to confirm the plan is done (tests, schema checks, manual verifications).

2. One phase = one file. If a single conceptual change spans multiple files, split into multiple phases (one per file) and note the cross-phase dependency in **Ordre d'exécution**.

3. End the response with the path to the generated `README.md` so the user can open it. Do not start implementing until the user explicitly asks for execution.

## Pointers

- High-level mental model → `docs/contributing/architecture.md`
- Helper contracts → `docs/contributing/scripts.md`
- Manifest + tree → `docs/contributing/structure.md`
- Decisions log → `docs/contributing/decisions.md`
- Skill-by-skill specs → `docs/usage/skills/`
- User-facing concepts → `docs/usage/concepts.md`
- Release notes → `CHANGELOG.md`
