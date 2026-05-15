# Plugin

## Distribution

Plugin packaged to the Claude Code schema: `.claude-plugin/plugin.json` manifest, MCP servers via `.mcp.json` at root, skills/agents auto-discovered from conventional folders.

- Install via the `bryanberger` marketplace (Phase 10): `/plugin marketplace add BryanBerger98/claude-plugins` then `/plugin install snap@bryanberger`
- Or manual clone: `git clone … ~/.claude/plugins/snap` (auto-loaded)
- Compatible with project install via `.claude/settings.json` (`extraKnownMarketplaces` + `enabledPlugins`)

**No custom symlink.** Official CC paths only.

## Manifest `.claude-plugin/plugin.json`

```json
{
  "name": "snap",
  "version": "0.1.0",
  "description": "Workflow produit Claude Code: 5 skills enchaînables (define → ticket → wireframe → develop → qa).",
  "author": { "name": "Bryan Berger", "email": "contact@bryanberger.dev" },
  "homepage": "https://github.com/BryanBerger98/snapship-plugin",
  "repository": { "type": "git", "url": "https://github.com/BryanBerger98/snapship-plugin" },
  "license": "MIT",
  "keywords": ["workflow", "product-management", "tickets", "wireframes", "code-review", "qa", "affine", "frame0"]
}
```

> **Only `name` is required** by the CC schema. The other fields are recommended metadata.

### Fields **not used** (and why)

| Field | Status | Reason |
|-------|--------|--------|
| `skills` | absent | Auto-discovery from `skills/` at plugin root |
| `agents` | absent | Auto-discovery from `agents/` at plugin root |
| `commands` | absent | Our slash commands are **skills**, not `commands/*.md` |
| `hooks` | absent | No plugin lifecycle |
| `mcpServers` | absent inline | Declared via separate `.mcp.json` (functionally equivalent) |
| `outputStyles` / `lspServers` | absent | Not relevant |

## Plugin repo layout

```
snapship-plugin/
├── .claude-plugin/
│   └── plugin.json                # CC manifest (name, version, metadata)
├── .mcp.json                      # bundled MCP servers (code-review-graph)
├── CHANGELOG.md                   # Keep-a-Changelog
├── NOTICE                         # community MCPs attributions
├── LICENSE                        # MIT
├── README.md
├── skills/                        # auto-discovered
│   ├── define/
│   ├── ticket/
│   ├── wireframe/
│   ├── develop/
│   ├── qa/
│   └── _shared/                   # shared scripts + templates + schemas (used by skills, not a standard CC folder)
├── agents/                        # auto-discovered (`snap-` prefix to avoid collision with project agents)
│   ├── snap-code-reviewer-technical.md
│   ├── snap-code-reviewer-functional.md
│   ├── snap-code-reviewer-security.md
│   ├── snap-code-reviewer-qa.md
│   └── snap-developer.md
└── docs/                          # internal specs (not distributed at runtime)
```

Full tree details: [structure.md](structure.md).

## Validation

```bash
claude plugin validate .          # or /plugin validate . in-session
```

CI runs this validation on every push (Phase 7.3).

## Install

### `bryanberger` marketplace (Phase 10)

```bash
/plugin marketplace add BryanBerger98/claude-plugins
/plugin install snap@bryanberger
```

### Global manual clone

```bash
git clone https://github.com/BryanBerger98/snapship-plugin ~/.claude/plugins/snap
```

Plugin auto-loaded on next Claude Code start.

### Project-scoped (team)

`.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "bryanberger": { "source": { "source": "github", "repo": "BryanBerger98/claude-plugins" } }
  },
  "enabledPlugins": { "snap@bryanberger": true }
}
```

## MCP servers

| MCP                 | Bundling     | Role                                             | Required by                                   |
| ------------------- | ------------ | ------------------------------------------------ | --------------------------------------------- |
| `code-review-graph` | **bundled**  | Knowledge graph (impact, flows, tests)           | `/develop` (warm-up), `/qa` (scope=impacted)  |
| `affine-mcp-server` | required     | Primary docs (PRD + features + galleries)       | `/define`, `/wireframe`, `/ticket`            |
| `frame0-mcp-server` | optional     | Wireframes shapes/pages/export                   | `/wireframe`                                  |
| `playwright`        | optional     | Headless browser screenshot                      | `/qa` if `wireframe_check.enabled=true`       |

`code-review-graph` is declared in `.mcp.json` (auto-start). Binary installed separately: `pipx install code-review-graph`. See [mcp-refs.md](../usage/mcp-refs.md) for other MCPs.

## Versioning

Manifest `version` = SemVer.

JSON schemas validated at runtime (see [configuration.md](../usage/configuration.md) validation section).

## docs-defaults templates

Bundled in `skills/_shared/templates/docs-defaults/` (opt-in push via `setup-config.sh` on first run). See [templates.md](templates.md).
