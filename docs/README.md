# SnapShip

Plugin Claude Code — workflow produit autonome, 5 skills enchaînables: définition produit → tickets → wireframes → développement → QA.

## Vision

Workflow propre, autonome, packagé en plugin CC v1. Patterns réécrits inline, aucune dépendance externe. Adaptatif plateformes tickets (GitHub/GitLab/JIRA) + docs (AFFiNE/Notion) + wireframes (Frame0).

## Skills

| Slash                | Rôle                                                          | Stockage primaire                     |
| -------------------- | ------------------------------------------------------------- | ------------------------------------- |
| `/snap:init`      | Bootstrap workspace (config + `.claude/product/`). 1× par projet. | `snapship.config.json` + `.claude/product/` |
| `/snap:define`    | Définit produit + features. Brainstorm PRD interactif.        | AFFiNE (PRD global + feature)         |
| `/snap:ticket`    | Génère tickets adaptés à plateforme depuis mini-PRD.          | Plateforme tickets                    |
| `/snap:wireframe` | Wireframes Frame0 multi-écrans liés aux tickets.              | Frame0 + AFFiNE gallery               |
| `/snap:develop`   | Développe ticket(s). Standalone + loop session/daemon.        | Code + commits atomiques              |
| `/snap:qa`        | Validation runtime: régression scope + wireframes Playwright. | Tests + Playwright vs Frame0          |

Chaining manuel (skill suggère prochain à fin). `/snap:init` est obligatoire avant tout autre skill — les autres skills exit early si `snapship.config.json` absent.

## Sommaire documentation

| Fichier                                    | Contenu                                                                            |
| ------------------------------------------ | ---------------------------------------------------------------------------------- |
| [plugin.md](plugin.md)                     | Manifest plugin, distribution, install, layout                                     |
| [structure.md](structure.md)               | File tree global + storage projet + index.md                                       |
| [config.md](config.md)                     | Config schema `snapship.config.json` + auto-discovery + fallback                    |
| [scripts.md](scripts.md)                   | Scripts partagés `_shared/` (load-config, adapters, helpers)                       |
| [workflow.md](workflow.md)                 | Détection plateformes + intégration docs/tickets + error handling                  |
| [modes.md](modes.md)                       | Flags `-a` autonomous, monitoring usage, telemetry, `--dry-run`, SessionStart hook |
| [mcp-refs.md](mcp-refs.md)                 | MCP servers: Frame0, AFFiNE, code-review-graph, Playwright                         |
| [coverage.md](coverage.md)                 | Couverture besoins user → skills mapping                                           |
| [diagram.md](diagram.md)                   | Diagrammes Mermaid: vue globale + zooms par skill + variantes                      |
| [roadmap.md](roadmap.md)                   | Étapes développement → publication marketplace → install user-side                 |
| [templates.md](templates.md)               | Templates docs bundlés (PRD global/feature, wireframes gallery)                    |
| [decisions.md](decisions.md)               | Décisions validées + history + validation pré-build                                |
| [skills/init.md](skills/init.md)           | Skill `/snap:init` — bootstrap workspace                                        |
| [skills/define.md](skills/define.md)       | Skill `/snap:define` — frontmatter, flags, steps                                |
| [skills/ticket.md](skills/ticket.md)       | Skill `/ticket` — frontmatter, flags, steps                                        |
| [skills/wireframe.md](skills/wireframe.md) | Skill `/wireframe` — frontmatter, flags, steps                                     |
| [skills/develop.md](skills/develop.md)     | Skill `/develop` — frontmatter, flags, steps + loop modes                          |
| [skills/qa.md](skills/qa.md)               | Skill `/qa` — frontmatter, flags, steps                                            |

## Décisions clés

- **Distribution:** plugin v1 via `.claude-plugin/plugin.json` (schema CC officiel) — marketplace `bryanberger` ou clone manuel
- **Config:** `snapship.config.json` racine projet, étend defaults bundlés
- **Auth:** absente config — MCP/CLI gèrent (`gh auth`, `glab auth`, `$AFFINE_API_TOKEN`)
- **Sources vérité:** AFFiNE primaire docs / plateforme primaire tickets / cache local minimal
- **Mode autonome:** flag `-a` partout via wrapper `ask-or-default.sh`
- **Resume:** flag `-r` partout (partial match feature_id)
- **Langue:** Français défaut, override `--lang en`

## Prérequis runtime

**Required:** Claude Code CLI, MCP `affine-mcp-server` (ou Notion équivalent), MCP `frame0-mcp-server`.

**Optional:** MCP `code-review-graph` (régression scope=impacted), MCP `playwright` (wireframe check), CLIs `gh`/`glab`/`jira` (fallback si MCP plateforme tickets absent).

## Build order

1. `/snap:init` (bootstrap, 1× par projet)
2. `/snap:define` (entry workflow)
3. `/snap:ticket`
4. `/snap:wireframe`
5. `/snap:develop`
6. `/snap:qa`

Voir [decisions.md](decisions.md) pour rationale ordre + alternatives écartées.
