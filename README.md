# Artysan

Plugin Claude Code — workflow produit autonome, 5 skills enchaînables: définition produit → tickets → wireframes → développement → QA.

## Skills

| Slash        | Rôle                                                          | Stockage primaire             |
| ------------ | ------------------------------------------------------------- | ----------------------------- |
| `/define`    | Définit produit + features. Brainstorm PRD interactif.        | AFFiNE (PRD global + feature) |
| `/ticket`    | Génère tickets adaptés à plateforme depuis mini-PRD.          | Plateforme tickets            |
| `/wireframe` | Wireframes Frame0 multi-écrans liés aux tickets.              | Frame0 + AFFiNE gallery       |
| `/develop`   | Développe ticket(s). Standalone + loop session/daemon.        | Code + commits atomiques      |
| `/qa`        | Validation runtime: régression scope + wireframes Playwright. | Tests + Playwright vs Frame0  |

## Quickstart

```bash
# Install (méthode marketplace, recommandée)
/plugin install artysan

# Ou clone manuel global
git clone https://github.com/bryanberger/artysan-plugin ~/.claude/plugins/artysan

# Premier projet
cd <mon-projet>
claude
# Dans session:
/define "feature description"
```

Setup wizard détecte `.git/config`, MCP servers actifs, test commands → écrit `artysan.config.json` racine projet.

## Prérequis

**Required:** Claude Code CLI, MCP `affine-mcp-server` (ou Notion équivalent).

**Optional:** MCP `frame0-mcp-server` (wireframes), MCP `code-review-graph` (régression scope=impacted), MCP `playwright-mcp` (wireframe check), CLIs `gh`/`glab`/`jira` (fallback si MCP plateforme tickets absent).

## Documentation

Specs complètes: voir `docs/` (sommaire, config, scripts, workflow, modes, MCP refs, decisions, roadmap, diagrammes).

## License

MIT. Voir [LICENSE](LICENSE).

## Status

`v0.1.0` — en développement actif. Pas encore publié marketplace.
