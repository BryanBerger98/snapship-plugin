# SnapShip

Plugin Claude Code — workflow produit autonome, 6 skills enchaînables (`define → ticket → wireframe → design → develop → qa`) + 2 utilitaires doc.

## Vision

Workflow propre, autonome, packagé en plugin CC v1. Patterns réécrits inline, aucune dépendance externe. Adaptatif plateformes tickets (GitHub/GitLab/JIRA) + docs (AFFiNE/Notion) + wireframes (Frame0/Penpot/Figma) + design hi-fi (Penpot/Figma).

## Skills

| Slash               | Rôle                                                          | Stockage primaire                     |
| ------------------- | ------------------------------------------------------------- | ------------------------------------- |
| `/snap:init`        | Bootstrap workspace (config + `.claude/product/`). 1× par projet. | `snapship.config.json` + `.claude/product/` |
| `/snap:define`      | Définit produit + features. Brainstorm PRD interactif.        | AFFiNE/Notion (PRD + pages parcours)  |
| `/snap:ticket`      | Décompose un PRD feature en tickets adaptés à la plateforme.  | Plateforme tickets + `tickets.json`   |
| `/snap:wireframe`   | Wireframes low-fi multi-écrans (Frame0/Penpot/Figma).         | Plateforme wireframe + gallery doc    |
| `/snap:design`      | Maquettes hi-fi pour un ticket/feature (Penpot/Figma). Optionnel. | Plateforme design + gallery doc   |
| `/snap:develop`     | Développe ticket(s). Standalone + loop session/daemon.        | Code + commits atomiques              |
| `/snap:qa`          | Validation runtime: régression scope + diff wireframe Playwright. | Tests + Playwright vs wireframes  |
| `/snap:doc-import`  | Importe des docs legacy dans la hiérarchie SnapShip. One-shot/projet. | AFFiNE/Notion + `domains.json` |
| `/snap:doc-update`  | Rafraîchit la doc fonctionnelle vivante post-ship.            | AFFiNE/Notion (pages parcours)        |

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
| [skills/init.md](skills/init.md)           | Skill `/snap:init` — usage, flags, pipeline                                        |
| [skills/define.md](skills/define.md)       | Skill `/snap:define` — usage, flags, pipeline                                      |
| [skills/ticket.md](skills/ticket.md)       | Skill `/snap:ticket` — usage, flags, pipeline                                      |
| [skills/wireframe.md](skills/wireframe.md) | Skill `/snap:wireframe` — usage, flags, pipeline + plateformes                     |
| [skills/design.md](skills/design.md)       | Skill `/snap:design` — maquettes hi-fi : usage, flags, pipeline + plateformes      |
| [skills/develop.md](skills/develop.md)     | Skill `/snap:develop` — usage, flags, pipeline + loop modes + config               |
| [skills/qa.md](skills/qa.md)               | Skill `/snap:qa` — usage, flags, pipeline + config                                 |
| [skills/doc-import.md](skills/doc-import.md) | Skill `/snap:doc-import` — usage, flags, stratégies, pipeline                     |
| [skills/doc-update.md](skills/doc-update.md) | Skill `/snap:doc-update` — usage, flags, pipeline                                |

## Décisions clés

- **Distribution:** plugin v1 via `.claude-plugin/plugin.json` (schema CC officiel) — marketplace `bryanberger` ou clone manuel
- **Config:** `snapship.config.json` racine projet, étend defaults bundlés
- **Auth:** absente config — MCP/CLI gèrent (`gh auth`, `glab auth`, `$AFFINE_API_TOKEN`)
- **Sources vérité:** AFFiNE primaire docs / plateforme primaire tickets / cache local minimal
- **Mode autonome:** flag `-a` partout via wrapper `ask-or-default.sh`
- **Resume:** flag `-r` partout (partial match feature_id)
- **Langue:** Français défaut, override `--lang en`

## Prérequis runtime

**Required:** Claude Code CLI, MCP docs `affine-mcp-server` (ou Notion équivalent), binaire `code-review-graph` sur PATH.

**Optional:** MCP wireframe `frame0`/`penpot`/`figma`, MCP design `penpot`/`figma`, MCP `playwright` (wireframe check `/snap:qa`), CLIs `gh`/`glab`/`jira` (fallback si MCP plateforme tickets absent).

## Build order

1. `/snap:init` (bootstrap, 1× par projet)
2. `/snap:define` (entrée workflow)
3. `/snap:ticket`
4. `/snap:wireframe`
5. `/snap:design` (optionnel)
6. `/snap:develop`
7. `/snap:qa`
8. `/snap:doc-update` (post-ship)

`/snap:doc-import` est un utilitaire one-shot à lancer après `/snap:init` quand le projet a déjà des docs legacy à importer.

Voir [decisions.md](decisions.md) pour rationale ordre + alternatives écartées.
