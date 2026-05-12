# MCP refs

## Frame0 MCP

- Repo: github.com/niklauslee/frame0-mcp-server (community, Niklaus Lee)
- Install: `npx -y frame0-mcp-server` dans `claude_desktop_config.json`
- Requirements: Frame0 v1.7.0+, Node.js v22+, API Server enabled
- 28 tools: shapes (rect/ellipse/text/line/polygon/connector/icon/image), pages (add/update/duplicate/delete), operations (move/align/group/ungroup/export), icons search, links

## figma-console-mcp (wireframe + design Figma)

- Repo: github.com/southleft/figma-console-mcp (communautaire, southleft)
- Licence: MIT, v1.23.0 (mai 2026), ~100 outils exposés, activement maintenu
- Install: `claude mcp add figma-console -s user -e FIGMA_ACCESS_TOKEN=figd_… -e ENABLE_MCP_APPS=true -- npx -y figma-console-mcp@latest`
- Prérequis utilisateur:
  - Figma Desktop lancé
  - Plugin "Desktop Bridge" installé dans Figma (Plugins → Browse → "Desktop Bridge") — canal WebSocket ports 9223–9232 (auto-détection failover)
  - Token API Figma personnel (var env `FIGMA_ACCESS_TOKEN`, généré via Figma → Settings → Personal access tokens)
  - Node.js 18+
- Outils clés:
  - `figma_execute` (code JS Plugin API brut, retour JSON nœuds créés) — surface principale pour CRUD pages/frames/shapes
  - `figma_get_design_system_kit` (variables, composants, styles + captures)
  - `figma_batch_create_variables` / `figma_batch_update_variables` (max 100 items/appel)
  - `figma_get_console_logs` / `figma_watch_console` (debugging)
  - `figma_lint_design` / `figma_scan_code_accessibility` (audits WCAG)
- Format données:
  - Couleurs: `{r, g, b, a}` plages 0-1 (pas 0-255) — à respecter dans tous les descripteurs
  - Exports: pas d'outil natif `exportAsync`. Mécanisme = `figma_execute` injectant `node.exportAsync()`, retour base64 inline dans JSON, décodage côté helper avant écriture disque
- Usage:
  - `/wireframe` (platform=figma) → `figma-helper.sh` → `figma_execute` (JS Plugin API construit côté helper, miroir surface penpot)
  - `/design` (platform=figma) → `figma-bridge-helper.sh` → CLI `bridge-ds compile` → injection sortie via `figma_execute` (transport `official`)

## Bridge CLI (compilateur YAML CSpec → Figma)

- **CLI séparé, pas serveur MCP.** Installé en dépendance Node.js, invoqué par `figma-bridge-helper.sh` côté skill `/design`.
- Repo: github.com/noemuch/bridge (MIT, v3.0.0 mars 2026, TypeScript)
- Install: `npm install -g @bridge-ds/cli` (ou dépendance projet design system)
- Commandes:
  - `bridge-ds setup` — initialise dépôt système design (structure KB)
  - `bridge-ds compile <cspec.yaml>` — compile YAML CSpec en scene graph JSON + code Figma Plugin API conforme (26 règles Figma appliquées automatiquement, "DS-compliant by construction")
  - `bridge-ds doctor` — diagnostic config + base de connaissance
  - `bridge-ds extract` — récupère données via API REST Figma (variables, composants existants)
  - `bridge-ds cron` — sync base de connaissance + PRs automatiques
- Format CSpec YAML: spécification déclarative composants (tokens, variants, slots), résolution `$token` vers variables Figma
- Transport sortie compilation (config skill `design.figma.bridge_transport`):
  - `official` (défaut) — code injecté automatiquement via `figma_execute` du serveur `figma-console-mcp`
  - `console` — code écrit dans fichier `.js`, utilisateur le colle manuellement dans console DevTools Figma (workflow sans MCP)

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
