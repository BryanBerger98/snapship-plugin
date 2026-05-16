# 🧭 Architecture

High-level mental model for working on snap (v1.2). Each section links to the deep-dive doc when you want more.

> **v1.2 product rename.** The product is now called **snap**, not `snapship`. User-facing surface renamed: `snap.config.json`, `.env.snap`, plugin manifest `name = "snap"`. The git repo keeps its historical name (`snapship-plugin`). The directory `.snap/` and agent prefix `snap-` were already aligned. Migration handled by `/snap:upgrade`.

## 🪨 Core principle: platform-first persistence, ephemeral local cache

Remote platforms (Notion / AFFiNE, Figma / Penpot / Frame0, Linear / Jira / GitHub / GitLab) are the **sources of truth**. The local workspace `.snap/` only **pre-generates**, **validates**, and **stages** content before pushing remote.

v1.2 went further: the persistent `.snap/tickets/` cache is **dropped**. The tracker is the *only* source of truth for tickets, Epics, Milestones, Versions. Skills lookup live; there is no offline mode.

What still lives locally and committable:

| Data                                  | Path                                  | Status      |
| ------------------------------------- | ------------------------------------- | ----------- |
| Vision, journeys, taxonomy            | `.snap/manifests/_taxonomy.json`      | persisted   |
| User-Story PRD (`/define` output)     | `.snap/stories/{story_id}/meta.json`  | persisted   |
| Worktrees                             | `./.worktrees/<branch-name>/`         | gitignored  |
| **Ticket runtime cache**              | `.snap/.runtime/<subject-id>/`        | **ephemeral, gitignored** |

→ See [structure.md](structure.md) for the full `.snap/` layout.

## 💨 Ephemeral runtime cache

Skills that need multi-turn working memory (drafts, AC, validation, fetched tracker payloads) write to a **per-subject** scratch directory that lives **one skill invocation**. Purged on EXIT (success or failure).

Helper: [`skills/_shared/cache-runtime.sh`](../../skills/_shared/cache-runtime.sh).

```
init   <subject-id>          # mkdir .snap/.runtime/<subject-id>/
write  <subject-id> <file>   # stdin → file (atomic via tmp+mv)
read   <subject-id> <file>   # cat file → stdout
exists <subject-id> [<file>] # exit 0/1
purge  <subject-id>          # trash-based delete, idempotent
path   <subject-id>          # echo absolute dir
id-gen [--prefix=NAME]       # NAME-YYYYMMDDTHHMMSS-XXXXXX
```

### Subject-id derivation

The subject-id isolates concurrent runs. It is **the** key to cache scoping — never share one between skills.

| Skill              | Subject-id source                                              |
| ------------------ | -------------------------------------------------------------- |
| `/snap:define`     | `prd-<prd_slug>` (or `id-gen --prefix=define` if vision/journey mode) |
| `/snap:ticket`     | `ticket-<story_id>`, or `id-gen --prefix=ticket-standalone` when `--standalone` |
| `/snap:develop`    | `develop-<story_id>` (story_id resolved from tracker payload)  |
| `/snap:qa`         | `qa-<story_id>`                                                |
| `/snap:wireframe`  | `wireframe-<story_id>`                                         |
| `/snap:design`     | `design-<story_id>`                                            |

### Files written under `<subject-id>/`

| File          | Producer                                  | Content                                                     |
| ------------- | ----------------------------------------- | ----------------------------------------------------------- |
| `ticket.json` | tracker fetch (`tickets-adapter.sh get`)  | Raw tracker payload of the focal ticket.                    |
| `parent.json` | tracker fetch (parent_epic + parent_story)| Raw payloads of the legal parents, fetched live.            |
| `refs.json`   | step that resolved external doc refs      | Hydrated `acceptance_criteria`, linked doc snapshots, etc.  |
| `digest.json` | `snap-ticket-digest` subagent             | Consumer-tailored brief (`brief_md`, `warnings`, …).        |
| `tickets.json` | `/snap:ticket` drafts                    | Pre-push drafts validated against `tickets.schema.json`.    |

### EXIT trap pattern

Every skill orchestrator that opens a subject **must** trap purge on EXIT:

```bash
set -euo pipefail
CACHE="skills/_shared/cache-runtime.sh"

SUBJECT_ID=$("$CACHE" id-gen --prefix=develop)
"$CACHE" init "$SUBJECT_ID"
trap '"$CACHE" purge "$SUBJECT_ID"' EXIT

# fetch + digest + work
tickets-adapter.sh get "$ticket_id" | "$CACHE" write "$SUBJECT_ID" ticket.json
# … run subagents, validate, push to tracker …
# trap fires on normal exit, error, or interrupt
```

Crash = lost drafts. Acceptable: the tracker has been the source of truth all along.

## 🧬 Skill anatomy

Each `/snap:*` command is a skill stored under `skills/<name>/`:

```
skills/<name>/
├── SKILL.md           # entrypoint — user-facing description + step orchestration
├── step-NN-*.md       # numbered pipeline steps (deterministic, idempotent)
├── agents/*.md        # optional sub-agents (reviewers, validators)
└── _shared/ → ../_shared (helpers shared across skills)
```

Steps run sequentially. Each step is idempotent — re-running a skill resumes from the last completed step (`/snap:<skill> -r`).

→ Per-skill pipelines documented in [`docs/usage/skills/`](../usage/skills/).

## 🔁 State machine

A feature progresses through terminal states stored in its manifest:

```
defined → ticketed → wireframed → designed → developed → qa-validated → shipped
```

Each skill advances the manifest. Skills refuse to run when the prerequisite state is missing.

> **v1.2 rename.** `feature_id` → `story_id` (big-bang, no alias). One snap "story" = one User Story deliverable. Affects manifest schema, `.snap/stories/` directory, `progress.sh --story-id=`, all step files. Migration on existing projects via `/snap:upgrade`.

## 🎫 Ticket hierarchy (v1.2)

The tracker hosts the ticket graph. Skills navigate it through `tickets-adapter.sh`.

```
Epic (story_type=epic, no branch, no commit)
├── User Story (branch + PR)
│   └── Task         (shares parent US branch)
├── Task             (own branch + PR)
└── Bug              (own branch + PR)

User Story standalone (Epic=∅)
└── Task

Task / Bug standalone (Epic=∅, US=∅, own branch + PR)
```

| story_type   | Legal parents          | Branch | Commit | Develop / QA |
| ------------ | ---------------------- | ------ | ------ | ------------ |
| `epic`       | none                   | no     | no     | no           |
| `user-story` | Epic, ∅                | yes    | yes    | yes          |
| `task`       | Epic, User Story, Bug, ∅ | yes  | yes    | yes          |
| `bug`        | Epic, User Story, ∅    | yes    | yes    | yes          |

Bug→Bug is forbidden. Bug→Task is allowed (technical sub-fixes). `commit_type` is free (Conventional Commits enum) and **not** coupled to `story_type` — the agent proposes a default (`feat` for US, `fix` for bug, …), user overrides.

## 📐 v1.2 schemas

All schemas in `skills/_shared/schemas/` enforce `additionalProperties: false`. Adding a key = bump version + update fixtures + entry in `CHANGELOG.md`.

### `tickets.schema.json`

- `story_type` **required**, enum `epic | user-story | task | bug`.
- `parent_epic_id` (tracker ID, nullable) — Epic parent for US / Task / Bug.
- `parent_story_id` (tracker ID or local_id, nullable) — US parent for Task / Bug.
- `target_version` (semver, optional, explicit per ticket — no inheritance). Mapped per platform via adapter `supports_version`.
- `commit_type` independent of `story_type` (free enum).
- Single `allOf` rule: `story_type=epic` forbids `branch_name` and `commit_sha`.
- `story_type=bug` with `parent_story` of type `bug` is rejected by adapter pre-push (not schema-level — the cache only holds tracker IDs, parent type lookup is runtime).

### `meta.schema.json`

- Drop opaque `epic_link`. Add structured `parent_epic_id` (tracker ID).
- Add `target_version`.
- Rename `feature_id` → `story_id` (pattern `^[0-9]{2}-[a-z0-9][a-z0-9-]*$` unchanged).

### `config.schema.json`

- `defaults.worktree.subtask_root` removed (decision 11). Final shape: `path`, `default_root`, `destroy`.
- Naming: `branch_pattern = "{type}/{ticket_id}"` (no more `{slug}`), `commit_pattern` token `{type}` → `{commit_type}`.

## 🧰 Shared helpers (`skills/_shared/`)

| Helper                    | Purpose                                                |
| ------------------------- | ------------------------------------------------------ |
| `load-config.sh`          | Resolve `snap.config.json` → stdout (no cache file)    |
| `load-env.sh`             | Parse `.env.snap` for tokens                           |
| `progress.sh`             | `start \| step \| finish \| resume` — central progress log |
| `cache-runtime.sh`        | Per-subject ephemeral cache (purge on EXIT)            |
| `sync-push.sh` / `sync-fetch.sh` | Write-through outbox + replay refs (remote sync) |
| `tickets-adapter.sh`      | Tracker API (GH / GitLab / Jira / Linear)              |
| `docs-adapter.sh`         | AFFiNE / Notion API                                    |
| `setup-snap-dir.sh`       | Scaffold `.snap/` at init                              |
| `taxonomy-state.sh`       | Read/write `.snap/manifests/_taxonomy.json`            |
| `telemetry.sh log`        | Append a telemetry event (unified signature)           |
| `detect-repo-templates.sh` | Detect repo-native `.github/.gitlab` templates        |
| `resolve-template.sh`     | Resolve template path: override > repo-native > bundled |

→ Full contracts in [scripts.md](scripts.md).

## 🤖 Subagents

Seven subagents live in `agents/`. The `snap-` prefix is mandatory to avoid collision with downstream-project agents. Each agent = **one bounded job, one model, one output JSON fence** (strict last-fence rule — the orchestrator only parses the final ```json fence in the response).

| Agent                            | Model  | Access     | Job                                                                  |
| -------------------------------- | ------ | ---------- | -------------------------------------------------------------------- |
| `snap-developer`                 | sonnet | write      | Apply aggregated reviewer feedback to a diff; emit residual severity. |
| `snap-code-reviewer-technical`   | sonnet | read-only  | Static technical review (clean code, conventions, lint smells).      |
| `snap-code-reviewer-functional`  | sonnet | read-only  | Functional review against acceptance criteria.                       |
| `snap-code-reviewer-security`    | sonnet | read-only  | Security review (secrets, injection, authz, dep CVEs).               |
| `snap-code-reviewer-qa`          | sonnet | read-only  | QA review (test plan, coverage, flakiness, regression scope).        |
| `snap-ticket-classifier`         | haiku  | read-only  | Fuzzy input → structured ticket drafts (decompose, classify story_type, cluster parents). |
| `snap-ticket-digest`             | haiku  | read-only  | Full tracker payload → consumer-tailored brief (developer / reviewer / designer / qa). |

### Pattern

- **Subagents do not nest.** Claude Code disallows it. The orchestrating skill spawns `snap-ticket-digest` **once**, then feeds the resulting `digest.json` to all parallel reviewers in the same invocation context — reviewers never spawn their own subagents.
- **Haiku for extraction-shaped jobs** (classify, condense). Sonnet for review and write jobs. ~10× cost reduction where it counts; latency stays under 2 s for digest spawns, parallelisable.
- **One job per agent.** A classifier never pushes to the tracker; a digest never enriches; a reviewer never edits. Lane discipline is enforced by the agent's `tools:` frontmatter (`snap-developer` is the only one with `Write` / `Edit`).
- **Last-fence JSON output.** Agents may stream reasoning text, but the orchestrator parses only the final ```json fence — any prior fences are ignored. Keeps the contract robust against verbose thinking.

→ Per-agent contracts: see each `agents/<name>.md`.

## 🔌 Plugin distribution

Two artifacts ship together:

- `.claude-plugin/plugin.json` — manifest read by Claude Code (`name = "snap"` since v1.2)
- `.mcp.json` — bundled MCP servers (currently `code-review-graph`)

Distributed via the [`bryanberger`](https://github.com/BryanBerger98/claude-plugins) marketplace (`name` in `marketplace.json`). The marketplace tracks a git tag (`source.ref`); bumping a release = retag + bump `version` and `ref` in `marketplace.json`.

→ See [plugin-manifest.md](plugin-manifest.md).

## 🧪 CI

`.github/workflows/validate.yml` runs on push/PR:

- `bats tests/` — full test suite
- `shellcheck` on `skills/**/*.sh`
- `scripts/validate-plugin.sh` — manifest sanity
- `jq empty` on bundled JSON schemas

A failing CI = no merge.

## 🗺️ Where things live

| Concern                  | Path                                       |
| ------------------------ | ------------------------------------------ |
| Skills                   | `skills/<name>/`                           |
| Shared helpers           | `skills/_shared/`                          |
| Bundled doc templates    | `templates/`                               |
| JSON schemas             | `skills/_shared/schemas/`                  |
| Subagents                | `agents/snap-*.md`                         |
| Tests                    | `tests/` (bats)                            |
| Plugin manifest          | `.claude-plugin/plugin.json`               |
| MCP bundling             | `.mcp.json`                                |
| Issue / PR templates     | `.github/ISSUE_TEMPLATE/`, `.github/PULL_REQUEST_TEMPLATE.md` |

---

> Need user-side docs? → [Usage](../usage/README.md)
