# SnapShip

Plugin Claude Code — workflow produit autonome, 5 skills enchaînables: définition produit → tickets → wireframes → développement → QA.

## Skills

| Slash                | Rôle                                                          | Stockage primaire             |
| -------------------- | ------------------------------------------------------------- | ----------------------------- |
| `/snap:init`      | Bootstrap workspace (config + `.claude/product/`). À lancer 1× par projet. | `snapship.config.json` racine projet |
| `/snap:define`    | Définit produit + features. Brainstorm PRD interactif.        | AFFiNE (PRD global + feature) |
| `/snap:ticket`    | Génère tickets adaptés à plateforme depuis mini-PRD.          | Plateforme tickets            |
| `/snap:wireframe` | Wireframes Frame0 multi-écrans liés aux tickets.              | Frame0 + AFFiNE gallery       |
| `/snap:develop`   | Développe ticket(s). Standalone + loop session/daemon.        | Code + commits atomiques      |
| `/snap:qa`        | Validation runtime: régression scope + wireframes Playwright. | Tests + Playwright vs Frame0  |

## Quickstart

```bash
# Install (marketplace bryanberger, Phase 10)
/plugin marketplace add bryanberger/claude-plugins
/plugin install snap@bryanberger

# Ou clone manuel global (auto-loaded au prochain démarrage CC)
git clone https://github.com/BryanBerger98/snapship-plugin ~/.claude/plugins/snap

# Premier projet
cd <mon-projet>
claude
# Dans session — bootstrap once:
/snap:init
# Puis première feature:
/snap:define "feature description"
```

`/snap:init` détecte `.git/config`, MCP servers actifs, test commands → écrit `snapship.config.json` racine projet + scaffold `.claude/product/`. Toutes les autres commandes (`/snap:define`, `/snap:ticket`, `/snap:wireframe`, `/snap:develop`, `/snap:qa`) refusent de s'exécuter sans config et pointent vers `/snap:init`.

## Prérequis

**Required:**

- Claude Code CLI
- MCP `affine-mcp-server` (ou Notion équivalent)
- Binaire `code-review-graph` sur PATH — bundled via `.mcp.json` (Claude Code démarre le serveur, mais ne l'installe pas):
  ```bash
  pipx install code-review-graph
  ```

**Optional:** MCP `frame0-mcp-server` (wireframes), MCP `playwright-mcp` (wireframe check `/qa`), CLIs `gh`/`glab`/`jira` (fallback si MCP plateforme tickets absent).

`/develop` et `/qa` dégradent gracieusement si `code-review-graph` absent (fallback `tests-only`), mais l'optimisation review (impact radius, affected flows) requiert le binaire.

## Documentation

Specs complètes dans [`docs/`](docs/README.md):

- [docs/structure.md](docs/structure.md) — file tree + storage projet
- [docs/config.md](docs/config.md) — schema `snapship.config.json`
- [docs/workflow.md](docs/workflow.md) — détection plateformes + intégration
- [docs/modes.md](docs/modes.md) — flags `-a`, telemetry, `--dry-run`, hooks
- [docs/mcp-refs.md](docs/mcp-refs.md) — Frame0, AFFiNE, code-review-graph, Playwright
- [docs/decisions.md](docs/decisions.md) — décisions validées + history
- [docs/roadmap/](docs/roadmap/README.md) — étapes dev → publication → install (1 fichier par phase)
- [docs/diagram.md](docs/diagram.md) — schémas Mermaid workflow
- [docs/skills/](docs/skills/) — specs détaillées par skill

## License

MIT. Voir [LICENSE](LICENSE).

## Status

`v0.1.0` — en développement actif. Pas encore publié marketplace.
