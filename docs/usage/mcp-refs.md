# MCP refs

## Frame0 MCP

- Repo: github.com/niklauslee/frame0-mcp-server (community, Niklaus Lee)
- Install: `npx -y frame0-mcp-server` in `claude_desktop_config.json`
- Requirements: Frame0 v1.7.0+, Node.js v22+, API Server enabled
- 28 tools: shapes (rect/ellipse/text/line/polygon/connector/icon/image), pages (add/update/duplicate/delete), operations (move/align/group/ungroup/export), icon search, links

## figma-console-mcp (wireframe + Figma design)

- Repo: github.com/southleft/figma-console-mcp (community, southleft)
- License: MIT, v1.23.0 (May 2026), ~100 tools exposed, actively maintained
- Install: `claude mcp add figma-console -s user -e FIGMA_ACCESS_TOKEN=figd_… -e ENABLE_MCP_APPS=true -- npx -y figma-console-mcp@latest`
- User prerequisites:
  - Figma Desktop running
  - "Desktop Bridge" plugin installed in Figma (Plugins → Browse → "Desktop Bridge") — WebSocket channel ports 9223–9232 (auto-detection failover)
  - Personal Figma API token (env var `FIGMA_ACCESS_TOKEN`, generated via Figma → Settings → Personal access tokens)
  - Node.js 18+
- Key tools:
  - `figma_execute` (raw Plugin API JS code, returns JSON of created nodes) — main surface for CRUD on pages/frames/shapes
  - `figma_get_design_system_kit` (variables, components, styles + screenshots)
  - `figma_batch_create_variables` / `figma_batch_update_variables` (max 100 items/call)
  - `figma_get_console_logs` / `figma_watch_console` (debugging)
  - `figma_lint_design` / `figma_scan_code_accessibility` (WCAG audits)
- Data format:
  - Colors: `{r, g, b, a}` ranges 0-1 (not 0-255) — must be respected in all descriptors
  - Exports: no native `exportAsync` tool. Mechanism = `figma_execute` injecting `node.exportAsync()`, returns inline base64 in JSON, decoded helper-side before writing to disk
- Usage:
  - `/wireframe` (platform=figma) → `figma-helper.sh` → `figma_execute` (Plugin API JS built helper-side, mirrors penpot surface)
  - `/design` (platform=figma) → `figma-helper.sh` → `figma_execute` — **same helper and same Desktop Bridge plugin** as `/wireframe figma`. `/design` only produces hi-fi mockups; the design system is managed outside the plugin.

## AFFiNE MCP

- Repo: github.com/DAWNCR0W/affine-mcp-server (community)
- Install: `npm i -g affine-mcp-server` or `npx -y affine-mcp-server` in MCP config
- Auth: API Token via Settings → Integrations → MCP Server (AFFiNE Cloud), or cookie/email for self-hosted
- 84 tools: documents (search/read/create/publish/move/tag/import/export, block-level mutation), databases (columns, rows), workspaces (CRUD), comments, history, notifications, blob storage
- Templates: native page templates (UI-driven). Skill duplicates via MCP, fills variables.
- Content model: block-based (notion-like) with markdown import/export

## code-review-graph MCP (bundled)

- Persistent incremental knowledge graph (Tree-sitter parser, structural graph)
- **Bundled via plugin root `.mcp.json`** — auto-starts when snap is active. No manual `claude mcp add`.
- **Binary prerequisite (not auto-installed by Claude Code):**

  ```bash
  pipx install code-review-graph   # recommended
  # or: pip install --user code-review-graph
  which code-review-graph          # must resolve
  ```

- Usage:
  - `/develop` step-02-prepare: `get_impact_radius` warm-up on ticket files
  - `/qa` step-01-collect regression scope=impacted:
    - `get_impact_radius` (on diff) → affected files/symbols
    - `get_affected_flows` → affected execution paths → tests to run
    - `query_graph pattern=tests_for` → coverage
- **Fallback `tests-only`** if binary absent (graph unavailable detected by `check-mcp-required.sh`) — run heuristic on transitive imports of diff files
- Upstream repo: github.com/tirth8205/code-review-graph

## Playwright MCP (optional — wireframe check)

- Required if `qa.wireframe_check.enabled=true`
- Repo: github.com/microsoft/playwright-mcp
- Install: `npx -y @playwright/mcp@latest` in MCP config
- Usage `/qa` step-01-collect wireframe: navigate feature URL → screenshot → diff vs Frame0 PNG export
- Listed in `mcp_servers_optional`. The `/qa` skill dynamically adds it to required check-list if the feature is on
- If MCP absent AND `wireframe_check.enabled=true` → `/qa` startup error
