# SnapShip

Plugin Claude Code — workflow produit autonome, 6 skills enchaînables (`define → ticket → wireframe → design → develop → qa`) + 2 utilitaires doc (`doc-import`, `doc-update`). Adaptatif plateformes tickets (GitHub/GitLab/JIRA), docs (AFFiNE/Notion), wireframes (Frame0/Penpot/Figma) et design hi-fi (Penpot/Figma).

## Skills

### Workflow principal

| Slash             | Rôle                                                                | Stockage primaire                        |
| ----------------- | ------------------------------------------------------------------- | ---------------------------------------- |
| `/snap:init`      | Bootstrap workspace (config + `.claude/product/`). À lancer 1× par projet. | `snapship.config.json` racine projet |
| `/snap:define`    | Définit produit + features. Brainstorm PRD interactif.              | AFFiNE/Notion (PRD + pages parcours)     |
| `/snap:ticket`    | Décompose un PRD feature en tickets adaptés à la plateforme.         | Plateforme tickets + `tickets.json`      |
| `/snap:wireframe` | Wireframes low-fi multi-écrans (Frame0/Penpot/Figma) liés aux tickets. | Plateforme wireframe + gallery doc     |
| `/snap:design`    | Maquettes hi-fi pour un ticket/feature (Penpot/Figma). Optionnel.   | Plateforme design + gallery doc          |
| `/snap:develop`   | Développe ticket(s). Standalone + loop session/daemon, 3 reviewers. | Code + commits atomiques + PR            |
| `/snap:qa`        | Validation runtime : régression scope + diff wireframe Playwright.  | Tests + Playwright vs wireframes         |

### Utilitaires documentation

| Slash               | Rôle                                                              | Stockage primaire        |
| ------------------- | ----------------------------------------------------------------- | ------------------------ |
| `/snap:doc-import`  | Importe des docs legacy dans la hiérarchie SnapShip. One-shot/projet. | AFFiNE/Notion + `domains.json` |
| `/snap:doc-update`  | Rafraîchit la doc fonctionnelle vivante après le ship d'une feature. | AFFiNE/Notion (pages parcours) |

Chaque skill a sa doc d'usage détaillée (flags, pipeline, outputs) dans [`docs/skills/`](docs/skills/).

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

`/snap:init` détecte `.git/config`, MCP servers actifs, test commands → écrit `snapship.config.json` racine projet + scaffold `.claude/product/`. Toutes les autres commandes refusent de s'exécuter sans config et pointent vers `/snap:init`.

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
- [docs/skills/](docs/skills/) — doc d'usage par skill (1 fichier par skill : flags, pipeline, outputs)

## License

MIT. Voir [LICENSE](LICENSE).

## Status

`v0.6.0` — en développement actif. Pas encore publié marketplace.
