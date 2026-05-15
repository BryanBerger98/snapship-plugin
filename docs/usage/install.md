# Installation

Snap is a **Claude Code plugin**. Three install paths, in order of preference:

1. **Marketplace** `bryanberger` (recommended — repo [`BryanBerger98/claude-plugins`](https://github.com/BryanBerger98/claude-plugins)).
2. **Manual global clone** under `~/.claude/plugins/` (alternative without marketplace).
3. **Project-scoped clone** under `<project>/.claude/plugins/` (pins one version
   per project).

> The plugin has **no automatic installer** for external MCPs/CLIs. Anything
> required at runtime (jq, `code-review-graph`, docs/design MCPs) must exist
> before the first `/snap:init`.

## 1. Marketplace (recommended)

```text
/plugin marketplace add BryanBerger98/claude-plugins
/plugin install snap@bryanberger
```

Update via `/plugin update snap@bryanberger`, uninstall via
`/plugin remove snap`. The marketplace tracks the git tag of the release
(`v1.0.0` currently) — each new plugin release bumps the marketplace, and
`/plugin update` pulls the new version.

## 2. Manual global clone

Snap is auto-loaded by Claude Code when present in `~/.claude/plugins/`. No
global configuration required.

```bash
git clone https://github.com/BryanBerger98/snapship-plugin ~/.claude/plugins/snap
```

Restart Claude Code. The `/snap:*` commands appear in the palette.

To update:

```bash
cd ~/.claude/plugins/snap && git pull
```

If the local tag and the remote tag diverge in **MAJOR**, run `/snap:upgrade`
on the next skill invocation — it detects the mismatch and migrates the
project's `.snap/`.

## 3. Project-scoped clone

When you want to **pin a version** to a specific repo (team, CI repro):

```bash
cd <project>
git clone https://github.com/BryanBerger98/snapship-plugin .claude/plugins/snap
echo ".claude/plugins/" >> .gitignore       # or commit deliberately
```

The local plugin **wins** over the global version. Useful to pin v1.0.0
while testing v1.1.0 globally.

## Runtime prerequisites

### Required

| Component                | Verify                        | Install                                      |
| ------------------------ | ----------------------------- | -------------------------------------------- |
| Claude Code CLI          | `claude --version`            | https://claude.com/code                      |
| `jq`                     | `jq --version`                | `brew install jq` / `apt install jq`         |
| `code-review-graph`      | `code-review-graph --help`    | `pipx install code-review-graph`             |
| Docs MCP (one of)        | `claude mcp list`             | `affine-mcp-server` or `notion-mcp-server`   |
| Design or wireframe MCP  | `claude mcp list`             | one of `figma`, `penpot`, `frame0`           |

`code-review-graph` is declared in the bundled `.mcp.json` — Claude Code
launches the server, **it does not install it**. If the binary is missing,
`/snap:develop` and `/snap:qa` run in degraded mode
(`qa.regression.scope=tests-only`, no impact radius).

### Optional

| Component            | What it's for                                           |
| -------------------- | ------------------------------------------------------- |
| MCP `playwright`     | `/snap:qa` visual wireframe diff                        |
| CLI `gh` / `glab`    | Fallback if GitHub/GitLab tickets MCP missing           |
| CLI `jira`           | JIRA tickets fallback                                   |

## Secrets — `.env.snapship`

Snap reads secrets **only** from `<project>/.env.snapship`. This file is
gitignored by default.

```dotenv
# .env.snapship — project root
FIGMA_ACCESS_TOKEN=figd_xxxxxxxxxxxxxxxxxxxx
# AFFINE_API_TOKEN and NOTION_TOKEN are read by the MCP servers themselves,
# not by snap directly.
```

Reader helper: `skills/_shared/load-env.sh --project-root=$PWD --key=FIGMA_ACCESS_TOKEN`.

| Key                   | When                                                  |
| --------------------- | ----------------------------------------------------- |
| `FIGMA_ACCESS_TOKEN`  | `wireframes.platform=figma` or `design.platform=figma`|

Override the key name via `wireframes.figma.token_env` / `design.figma.token_env`
in `snapship.config.json` (e.g. `FIGMA_DEV_TOKEN`).

## Verification

```bash
cd <project>
claude
```

In the session:

```text
/snap:init --dry-run        # (not yet implemented — use /snap:init then abort)
/plugin list                 # snap@1.0.0 must appear
```

If `/snap:*` doesn't appear: restart Claude Code, check the install path,
check `~/.claude/plugins/snap/.claude-plugin/plugin.json`.

## Next step

[getting-started.md](getting-started.md) — first `/snap:init` then your first
feature with `/snap:define`.
