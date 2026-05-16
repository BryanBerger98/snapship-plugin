# 🧭 Architecture

High-level mental model for working on SnapShip. Each section links to the deep-dive doc when you want more.

## 🪨 Core principle: remote-first

Remote platforms (Notion / AFFiNE, Figma / Penpot / Frame0, Linear / Jira / GitHub / GitLab) are the **sources of truth**. The local workspace (`.snap/`) only **pre-generates**, **validates**, and **stages** content before pushing it remote.

Ideally nothing lives locally except references to remote resources. The two exceptions are `.snap/manifests/` (feature state) and `.snap/tickets/` (cache needed by `/develop` and `/qa` to resume offline).

→ See [structure.md](structure.md) for the full `.snap/` layout.

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

## 🧰 Shared helpers (`skills/_shared/`)

| Helper                    | Purpose                                                |
| ------------------------- | ------------------------------------------------------ |
| `load-config.sh`          | Resolve `snap.config.json` → stdout (no cache file) |
| `load-env.sh`             | Parse `.env.snap` for tokens                       |
| `progress.sh`             | `start | step | finish | resume` — central progress log |
| `sync-push.sh` / `sync-fetch.sh` | Write-through outbox + replay refs (remote sync) |
| `setup-snap-dir.sh`       | Scaffold `.snap/` at init                              |
| `taxonomy-state.sh`       | Read/write `.snap/manifests/_taxonomy.json`            |
| `telemetry.sh log`        | Append a telemetry event (unified signature)           |
| `detect-repo-templates.sh` | Detect repo-native `.github/.gitlab` templates        |
| `resolve-template.sh`     | Resolve template path: override > repo-native > bundled |

→ Full contracts in [scripts.md](scripts.md).

## 🔌 Plugin distribution

Two artifacts ship together:

- `.claude-plugin/plugin.json` — manifest read by Claude Code
- `.mcp.json` — bundled MCP servers (currently `code-review-graph`)

Distributed via the [`bryanberger`](https://github.com/BryanBerger98/claude-plugins) marketplace (`name` in `marketplace.json`). The marketplace tracks a git tag (`source.ref`); bumping a release = retag + bump `version` and `ref` in `marketplace.json`.

→ See [plugin-manifest.md](plugin-manifest.md).

## 🧪 CI

`.github/workflows/validate.yml` runs on push/PR:

- `bats tests/` — full test suite (~1269 cases)
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
| JSON schemas             | `schemas/`                                 |
| Tests                    | `tests/` (bats)                            |
| Plugin manifest          | `.claude-plugin/plugin.json`               |
| MCP bundling             | `.mcp.json`                                |
| Issue / PR templates     | `.github/ISSUE_TEMPLATE/`, `.github/PULL_REQUEST_TEMPLATE.md` |

---

> Need user-side docs? → [Usage](../usage/README.md)
