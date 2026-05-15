# SnapShip

[![release](https://img.shields.io/github/v/release/BryanBerger98/snapship-plugin?label=release)](https://github.com/BryanBerger98/snapship-plugin/releases)
[![marketplace](https://img.shields.io/badge/install-snap%40bryanberger-blue)](https://github.com/BryanBerger98/claude-plugins)
[![license](https://img.shields.io/badge/license-MIT-green)](LICENSE)

Plugin Claude Code — workflow produit autonome, 6 skills enchaînables (`define → ticket → wireframe → design → develop → qa`) + 2 utilitaires doc (`doc-import`, `doc-update`). Adaptatif plateformes tickets (GitHub/GitLab/JIRA), docs (AFFiNE/Notion), wireframes (Frame0/Penpot/Figma) et design hi-fi (Penpot/Figma).

## Skills

### Workflow principal

| Slash             | Rôle                                                                | Stockage primaire                        |
| ----------------- | ------------------------------------------------------------------- | ---------------------------------------- |
| `/snap:init`      | Bootstrap workspace (config + `.snap/`). À lancer 1× par projet. | `snapship.config.json` racine projet |
| `/snap:define`    | Définit produit + features. Brainstorm PRD interactif.              | AFFiNE/Notion (PRD + pages parcours)     |
| `/snap:ticket`    | Décompose un PRD feature en tickets adaptés à la plateforme.         | Plateforme tickets + `tickets.json`      |
| `/snap:wireframe` | Wireframes low-fi multi-écrans (Frame0/Penpot/Figma) liés aux tickets. | Plateforme wireframe + gallery doc     |
| `/snap:design`    | Maquettes hi-fi pour un ticket/feature (Penpot/Figma). Optionnel.   | Plateforme design + gallery doc          |
| `/snap:develop`   | Développe ticket(s). Standalone + loop session, 3 reviewers. | Code + commits atomiques + PR            |
| `/snap:qa`        | Validation runtime : régression scope + diff wireframe Playwright.  | Tests + Playwright vs wireframes         |

### Utilitaires documentation

| Slash               | Rôle                                                              | Stockage primaire        |
| ------------------- | ----------------------------------------------------------------- | ------------------------ |
| `/snap:doc-import`  | Importe des docs legacy dans la hiérarchie SnapShip. One-shot/projet. | AFFiNE/Notion + `.snap/manifests/_taxonomy.json` |
| `/snap:doc-update`  | Rafraîchit la doc fonctionnelle vivante après le ship d'une feature. | AFFiNE/Notion (pages parcours) |

Chaque skill a sa doc d'usage détaillée (flags, pipeline, outputs) dans [`docs/skills/`](docs/skills/).

## Quickstart (5 min)

```bash
# 1. Install via marketplace bryanberger (recommandé)
#    Dans une session claude :
#    /plugin marketplace add BryanBerger98/claude-plugins
#    /plugin install snap@bryanberger
#
#    Ou clone manuel global :
git clone https://github.com/BryanBerger98/snapship-plugin ~/.claude/plugins/snap

# 2. Lance Claude Code dans ton projet
cd <mon-projet>
claude

# 3. Dans la session — bootstrap une fois par projet
/snap:init                          # interactif : détecte plateformes & demande confirmation
# (ou /snap:init --auto pour utiliser tous les defaults détectés)

# 4. Première feature
/snap:define "Authentification email + magic link"
/snap:ticket  01-auth-email
/snap:develop 01-auth-email
/snap:qa      01-auth-email
```

`/snap:init` détecte `.git/config`, les MCP servers actifs, la structure projet → écrit `snapship.config.json` racine projet et scaffold `.snap/`. Toutes les autres commandes refusent de s'exécuter sans cette config et pointent vers `/snap:init`.

Détails install + prérequis : [docs/install.md](docs/install.md). Walkthrough complet : [docs/getting-started.md](docs/getting-started.md). Migration v0.6 → v1.0 : [docs/migration-v1.md](docs/migration-v1.md).

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
- [docs/install.md](docs/install.md) — install (marketplace + clone) + prérequis
- [docs/getting-started.md](docs/getting-started.md) — premier `/snap:init` puis première feature
- [docs/troubleshooting.md](docs/troubleshooting.md) — erreurs courantes (auth MCP, secrets, resume, sync)
- [docs/configuration.md](docs/configuration.md) — schema `snapship.config.json`
- [docs/migration-v1.md](docs/migration-v1.md) — guide migration v0.6 → v1.0
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

`v1.0.0` — refactor breaking (remote-first, `.snap/` réorganisé). Publié via marketplace [`BryanBerger98/claude-plugins`](https://github.com/BryanBerger98/claude-plugins) (`/plugin install snap@bryanberger`). Upgrade depuis v0.6.x : `/snap:upgrade` (voir [docs/migration-v1.md](docs/migration-v1.md)).
