<div align="center">

# 🚢 SnapShip

**Ship product features end-to-end inside Claude Code.**

[![release](https://img.shields.io/github/v/release/BryanBerger98/snapship-plugin?label=release)](https://github.com/BryanBerger98/snapship-plugin/releases)
[![marketplace](https://img.shields.io/badge/install-snap%40bryanberger-blue)](https://github.com/BryanBerger98/claude-plugins)
[![license](https://img.shields.io/badge/license-MIT-green)](LICENSE)

</div>

SnapShip is a Claude Code plugin that turns a one-line feature idea into a shipped, QA'd pull request — **without leaving your terminal**. It chains six product skills (`define → ticket → wireframe → design → develop → qa`) and two doc utilities, and adapts to the platforms you already use.

| 🎯 You bring                                | 🤖 SnapShip handles                                                                  |
| ------------------------------------------- | ------------------------------------------------------------------------------------ |
| A repo + a feature idea                     | PRD, tickets, wireframes, hi-fi mockups, code, reviews, regression tests             |
| Tickets in GitHub / GitLab / JIRA           | Auto-detects your platform and pushes there — no glue code, no extra config         |
| Docs in AFFiNE / Notion                     | Brainstorms PRDs interactively, syncs back to your knowledge base                    |
| Designs in Frame0 / Penpot / Figma          | Generates low-fi wireframes, optional hi-fi mockups, Playwright diffs them against the UI |

---

## ✨ Skills

### Core workflow

| Slash             | What it does                                                       | Primary storage                          |
| ----------------- | ------------------------------------------------------------------ | ---------------------------------------- |
| `/snap:init`      | Bootstraps the workspace (config + `.snap/`). Run once per project. | `snapship.config.json` at project root   |
| `/snap:define`    | Interactive PRD brainstorm — product + features.                    | AFFiNE / Notion (PRD + journey pages)    |
| `/snap:ticket`    | Breaks a feature PRD into tickets fit for your platform.            | Tickets platform + `tickets.json`        |
| `/snap:wireframe` | Multi-screen low-fi wireframes, linked to tickets.                  | Wireframe platform + gallery doc         |
| `/snap:design`    | Optional hi-fi mockups for a ticket / feature.                      | Design platform + gallery doc            |
| `/snap:develop`   | Implements ticket(s). Standalone or session loop. 3 reviewers.      | Code + atomic commits + PR               |
| `/snap:qa`        | Runtime validation: regression scope + Playwright wireframe diff.   | Tests + Playwright vs wireframes         |

### 📚 Documentation utilities

| Slash               | What it does                                                       | Primary storage                                  |
| ------------------- | ------------------------------------------------------------------ | ------------------------------------------------ |
| `/snap:doc-import`  | Imports existing docs into the SnapShip hierarchy. One-shot.        | AFFiNE / Notion + `.snap/manifests/_taxonomy.json` |
| `/snap:doc-update`  | Refreshes the living functional doc after a feature ships.          | AFFiNE / Notion (journey pages)                  |

> 📖 Each skill has a dedicated usage doc (flags, pipeline, outputs) under [`docs/usage/skills/`](docs/usage/skills/).

---

## 🚀 Quickstart (5 min)

**1. Install via the `bryanberger` marketplace** (recommended) — inside a Claude Code session:

```text
/plugin marketplace add BryanBerger98/claude-plugins
/plugin install snap@bryanberger
```

Or clone manually:

```bash
git clone https://github.com/BryanBerger98/snapship-plugin ~/.claude/plugins/snap
```

**2. Launch Claude Code in your project:**

```bash
cd <your-project>
claude
```

**3. Bootstrap (once per project):**

```text
/snap:init           # interactive — detects platforms + asks for confirmation
# or /snap:init --auto to take every detected default
```

**4. Ship your first feature:**

```text
/snap:define   "Email + magic-link authentication"
/snap:ticket   01-auth-email
/snap:develop  01-auth-email
/snap:qa       01-auth-email
```

> 💡 `/snap:init` reads `.git/config`, active MCP servers, and your project layout — then writes `snapship.config.json` and scaffolds `.snap/`. Every other skill refuses to run without that config and points back to `/snap:init`.

📂 Install + prerequisites → [docs/usage/install.md](docs/usage/install.md)
🎬 Full walkthrough → [docs/usage/getting-started.md](docs/usage/getting-started.md)

---

## 🛠️ Prerequisites

### ✅ Required

- Claude Code CLI
- MCP `affine-mcp-server` (or a Notion equivalent)
- `code-review-graph` binary on `PATH` — bundled via `.mcp.json` (Claude Code starts the server but **does not install it**):
  ```bash
  pipx install code-review-graph
  ```

### 🧩 Optional

- MCP `frame0-mcp-server` — wireframes
- MCP `playwright-mcp` — `/snap:qa` wireframe diff
- CLIs `gh` / `glab` / `jira` — fallback when the tickets MCP is absent

> ℹ️ `/snap:develop` and `/snap:qa` degrade gracefully without `code-review-graph` (fallback: `tests-only`), but review optimisation (impact radius, affected flows) needs the binary.

---

## 📖 Documentation

Full specs in [`docs/`](docs/README.md) — split between **usage** (for plugin users) and **contributing** (for plugin developers).

### 👤 Usage

| 📄 Doc                                                | What's inside                                              |
| ----------------------------------------------------- | ---------------------------------------------------------- |
| [install.md](docs/usage/install.md)                   | Install paths (marketplace + clone) + prerequisites        |
| [getting-started.md](docs/usage/getting-started.md)   | First `/snap:init` then first feature                      |
| [configuration.md](docs/usage/configuration.md)       | `snapship.config.json` schema                              |
| [workflow.md](docs/usage/workflow.md)                 | Platform detection + integration                           |
| [modes.md](docs/usage/modes.md)                       | Flags `-a`, telemetry, `--dry-run`, hooks                  |
| [mcp-refs.md](docs/usage/mcp-refs.md)                 | Frame0, AFFiNE, code-review-graph, Playwright references   |
| [concepts.md](docs/usage/concepts.md)                 | PRD vs living functional doc (journeys)                    |
| [diagram.md](docs/usage/diagram.md)                   | Mermaid diagrams of the workflow                           |
| [troubleshooting.md](docs/usage/troubleshooting.md)   | Common errors (MCP auth, secrets, resume, sync)            |
| [skills/](docs/usage/skills/)                         | Per-skill usage docs (flags, pipeline, outputs)            |

### 🛠️ Contributing

| 📄 Doc                                                  | What's inside                                            |
| ------------------------------------------------------- | -------------------------------------------------------- |
| [architecture.md](docs/contributing/architecture.md)    | Skill anatomy, state machine, shared helpers             |
| [plugin-manifest.md](docs/contributing/plugin-manifest.md) | Plugin manifest, distribution, layout                  |
| [structure.md](docs/contributing/structure.md)          | File tree + project storage layout                       |
| [scripts.md](docs/contributing/scripts.md)              | `_shared/` helpers contracts                             |
| [templates.md](docs/contributing/templates.md)          | Bundled doc templates                                    |
| [decisions.md](docs/contributing/decisions.md)          | Validated decisions + history                            |

---

## 📦 Status

**`v1.0.0`** — remote-first workspace.

Published via the [`BryanBerger98/claude-plugins`](https://github.com/BryanBerger98/claude-plugins) marketplace → `/plugin install snap@bryanberger`.

---

## 📜 License

MIT — see [LICENSE](LICENSE).
