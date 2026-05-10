# MCP refs

## Frame0 MCP

- Repo: github.com/niklauslee/frame0-mcp-server (community, Niklaus Lee)
- Install: `npx -y frame0-mcp-server` dans `claude_desktop_config.json`
- Requirements: Frame0 v1.7.0+, Node.js v22+, API Server enabled
- 28 tools: shapes (rect/ellipse/text/line/polygon/connector/icon/image), pages (add/update/duplicate/delete), operations (move/align/group/ungroup/export), icons search, links

## AFFiNE MCP

- Repo: github.com/DAWNCR0W/affine-mcp-server (community)
- Install: `npm i -g affine-mcp-server` ou `npx -y affine-mcp-server` dans config MCP
- Auth: API Token via Settings → Integrations → MCP Server (AFFiNE Cloud), ou cookie/email pour self-hosted
- 84 tools: documents (search/read/create/publish/move/tag/import/export, block-level mutation), databases (columns, rows), workspaces (CRUD), comments, history, notifications, blob storage
- Templates: pages templates natives (UI-driven). Skill duplique via MCP, remplit variables.
- Content model: block-based (notion-like) avec markdown import/export

## code-review-graph MCP (bundled)

- Persistent incremental knowledge graph (Tree-sitter parser, structural graph)
- **Bundled via `.mcp.json` racine plugin** — auto-démarre quand snap activé. Pas de `claude mcp add` manuel.
- **Prérequis binaire (non auto-installé par Claude Code):**
  ```bash
  pipx install code-review-graph   # recommandé
  # ou: pip install --user code-review-graph
  which code-review-graph          # doit résoudre
  ```
- Usage:
  - `/develop` step-02-prepare: `get_impact_radius` warm-up sur fichiers ticket
  - `/qa` step-01-collect régression scope=impacted:
    - `get_impact_radius` (sur diff) → fichiers/symbols touchés
    - `get_affected_flows` → execution paths impactés → tests à run
    - `query_graph pattern=tests_for` → couverture
- **Fallback `tests-only`** si binaire absent (graph unavailable détecté par `check-mcp-required.sh`) — run heuristique imports transitifs sur fichiers diff
- Repo upstream: github.com/tirth8205/code-review-graph

## Playwright MCP (optionnel — wireframe check)

- Requis si `qa.wireframe_check.enabled=true`
- Repo: github.com/microsoft/playwright-mcp
- Install: `npx -y @playwright/mcp@latest` dans config MCP
- Usage `/qa` step-01-collect wireframe: navigate URL feature → screenshot → diff vs Frame0 PNG export
- Listé dans `mcp_servers_optional`. Skill `/qa` ajoute dynamiquement à check-list required si feature on
- Si MCP absent ET `wireframe_check.enabled=true` → erreur startup `/qa`
