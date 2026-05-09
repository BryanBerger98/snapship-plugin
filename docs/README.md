# Artysan

Plugin Claude Code — workflow produit autonome, 5 skills enchaînables: définition produit → tickets → wireframes → développement → QA.

## Vision

Workflow propre, autonome, packagé en plugin CC v1. Patterns réécrits inline, aucune dépendance externe. Adaptatif plateformes tickets (GitHub/GitLab/JIRA) + docs (AFFiNE/Notion) + wireframes (Frame0).

## Skills

| Slash        | Rôle                                                          | Stockage primaire             |
| ------------ | ------------------------------------------------------------- | ----------------------------- |
| `/define`    | Définit produit + features. Brainstorm PRD interactif.        | AFFiNE (PRD global + feature) |
| `/ticket`    | Génère tickets adaptés à plateforme depuis mini-PRD.          | Plateforme tickets            |
| `/wireframe` | Wireframes Frame0 multi-écrans liés aux tickets.              | Frame0 + AFFiNE gallery       |
| `/develop`   | Développe ticket(s). Standalone + loop session/daemon.        | Code + commits atomiques      |
| `/qa`        | Validation runtime: régression scope + wireframes Playwright. | Tests + Playwright vs Frame0  |

Chaining manuel (skill suggère prochain à fin).

## Sommaire documentation

| Fichier                                    | Contenu                                                                            |
| ------------------------------------------ | ---------------------------------------------------------------------------------- |
| [plugin.md](plugin.md)                     | Manifest plugin, distribution, install, layout                                     |
| [structure.md](structure.md)               | File tree global + storage projet + index.md                                       |
| [config.md](config.md)                     | Config schema `artysan.config.json` + auto-discovery + fallback                    |
| [scripts.md](scripts.md)                   | Scripts partagés `_shared/` (load-config, adapters, helpers)                       |
| [workflow.md](workflow.md)                 | Détection plateformes + intégration docs/tickets + error handling                  |
| [modes.md](modes.md)                       | Flags `-a` autonomous, monitoring usage, telemetry, `--dry-run`, SessionStart hook |
| [mcp-refs.md](mcp-refs.md)                 | MCP servers: Frame0, AFFiNE, code-review-graph, Playwright                         |
| [coverage.md](coverage.md)                 | Couverture besoins user → skills mapping                                           |
| [diagram.md](diagram.md)                   | Diagrammes Mermaid: vue globale + zooms par skill + variantes                      |
| [roadmap.md](roadmap.md)                   | Étapes développement → publication marketplace → install user-side                 |
| [templates.md](templates.md)               | Templates docs bundlés (PRD global/feature, wireframes gallery)                    |
| [decisions.md](decisions.md)               | Décisions validées + history + validation pré-build                                |
| [skills/define.md](skills/define.md)       | Skill `/define` — frontmatter, flags, steps                                        |
| [skills/ticket.md](skills/ticket.md)       | Skill `/ticket` — frontmatter, flags, steps                                        |
| [skills/wireframe.md](skills/wireframe.md) | Skill `/wireframe` — frontmatter, flags, steps                                     |
| [skills/develop.md](skills/develop.md)     | Skill `/develop` — frontmatter, flags, steps + loop modes                          |
| [skills/qa.md](skills/qa.md)               | Skill `/qa` — frontmatter, flags, steps                                            |

## Décisions clés

- **Distribution:** plugin v1 via `.claude-plugin/plugin.json` (schema CC officiel) — marketplace `bryanberger` ou clone manuel
- **Config:** `artysan.config.json` racine projet, étend defaults bundlés
- **Auth:** absente config — MCP/CLI gèrent (`gh auth`, `glab auth`, `$AFFINE_API_TOKEN`)
- **Sources vérité:** AFFiNE primaire docs / plateforme primaire tickets / cache local minimal
- **Mode autonome:** flag `-a` partout via wrapper `ask-or-default.sh`
- **Resume:** flag `-r` partout (partial match feature_id)
- **Langue:** Français défaut, override `--lang en`

## Prérequis runtime

**Required:** Claude Code CLI, MCP `affine-mcp-server` (ou Notion équivalent), MCP `frame0-mcp-server`.

**Optional:** MCP `code-review-graph` (régression scope=impacted), MCP `playwright` (wireframe check), CLIs `gh`/`glab`/`jira` (fallback si MCP plateforme tickets absent).

## Build order

1. `/define` (entry workflow)
2. `/ticket`
3. `/wireframe`
4. `/develop`
5. `/qa`

Voir [decisions.md](decisions.md) pour rationale ordre + alternatives écartées.
