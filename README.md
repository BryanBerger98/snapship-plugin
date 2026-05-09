# Artysan

Plugin Claude Code — workflow produit autonome, 5 skills enchaînables: définition produit → tickets → wireframes → développement → QA.

## Skills

| Slash                | Rôle                                                          | Stockage primaire             |
| -------------------- | ------------------------------------------------------------- | ----------------------------- |
| `/artysan:init`      | Bootstrap workspace (config + `.claude/product/`). À lancer 1× par projet. | `artysan.config.json` racine projet |
| `/artysan:define`    | Définit produit + features. Brainstorm PRD interactif.        | AFFiNE (PRD global + feature) |
| `/artysan:ticket`    | Génère tickets adaptés à plateforme depuis mini-PRD.          | Plateforme tickets            |
| `/artysan:wireframe` | Wireframes Frame0 multi-écrans liés aux tickets.              | Frame0 + AFFiNE gallery       |
| `/artysan:develop`   | Développe ticket(s). Standalone + loop session/daemon.        | Code + commits atomiques      |
| `/artysan:qa`        | Validation runtime: régression scope + wireframes Playwright. | Tests + Playwright vs Frame0  |

## Quickstart

```bash
# Install (marketplace bryanberger, Phase 10)
/plugin marketplace add bryanberger/claude-plugins
/plugin install artysan@bryanberger

# Ou clone manuel global (auto-loaded au prochain démarrage CC)
git clone https://github.com/BryanBerger98/artysan-plugin ~/.claude/plugins/artysan

# Premier projet
cd <mon-projet>
claude
# Dans session — bootstrap once:
/artysan:init
# Puis première feature:
/artysan:define "feature description"
```

`/artysan:init` détecte `.git/config`, MCP servers actifs, test commands → écrit `artysan.config.json` racine projet + scaffold `.claude/product/`. Toutes les autres commandes (`/artysan:define`, `/artysan:ticket`, `/artysan:wireframe`, `/artysan:develop`, `/artysan:qa`) refusent de s'exécuter sans config et pointent vers `/artysan:init`.

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
- [docs/config.md](docs/config.md) — schema `artysan.config.json`
- [docs/workflow.md](docs/workflow.md) — détection plateformes + intégration
- [docs/modes.md](docs/modes.md) — flags `-a`, telemetry, `--dry-run`, hooks
- [docs/mcp-refs.md](docs/mcp-refs.md) — Frame0, AFFiNE, code-review-graph, Playwright
- [docs/decisions.md](docs/decisions.md) — décisions validées + history
- [docs/roadmap.md](docs/roadmap.md) — étapes dev → publication → install
- [docs/diagram.md](docs/diagram.md) — schémas Mermaid workflow
- [docs/skills/](docs/skills/) — specs détaillées par skill

## License

MIT. Voir [LICENSE](LICENSE).

## Status

`v0.1.0` — en développement actif. Pas encore publié marketplace.
