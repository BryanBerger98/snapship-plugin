---
name: fetch
description: Re-synchronise le local depuis les plateformes distantes (Notion/AFFiNE pour PRDs/galleries, Figma/Penpot pour design files, Linear/GitHub pour tickets). Cas d'usage — édition d'un PRD synced, doc modifiée à distance, après /snap:upgrade.
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, AskUserQuestion
---

# /snap:fetch — re-sync local depuis remote

Remote = source de vérité. Ce skill rapatrie le contenu distant dans le staging
local (`.snap/PRDs/`, `.snap/designs/`, etc.) pour édition ou refresh, et met à
jour `manifests/{slug}.manifest.json.refs.*.synced_at` + `sync_status=synced`.

## Quand utiliser

- PRD modifié sur Notion/AFFiNE, on veut récupérer la dernière version locale.
- Avant un re-push (`/snap:define --refresh`), pour partir de la version remote.
- Après `/snap:upgrade`, pour absorber drift remote ↔ local.
- Désync detection : `/snap:fetch --check` flag manifests dont remote > local.

## Pipeline

| # | Step | Purpose |
|---|------|---------|
| 00 | `step-00-resolve.md` | Parse args, résout features + kinds à fetch depuis manifests |
| 01 | `step-01-fetch.md`   | Pull contenu remote via docs-adapter / figma-helper / tickets-adapter |
| 02 | `step-02-write.md`   | Écrit staging files dans `.snap/PRDs/`, `designs/`, etc. |
| 03 | `step-03-update.md`  | Update manifest refs (synced_at + sync_status) |

## Args

```
/snap:fetch [--feature=SLUG] [--kind=prd|design|wireframe|tickets|all] [--all] [--check] [--dry-run]
```

- `--feature=SLUG` : feature_id ciblée (ex: `01-auth`). Sans, dépend de `--all`.
- `--kind=K` : type de ressource (défaut `all` si feature passée).
- `--all` : toutes les features du workspace.
- `--check` : **opt-in désync detection**. Ne télécharge rien.
  Compare `manifests/*.refs.<kind>.synced_at` vs `last_edited_time` remote.
  Si remote > local → marque `sync_status="dirty"` et liste.
- `--dry-run` : montre plan sans écrire.

## Combinaisons

| Args | Effet |
|---|---|
| `--feature=01-auth --kind=prd` | Pull PRD de 01-auth uniquement. |
| `--feature=01-auth --kind=all` | Pull tous les kinds de 01-auth. |
| `--all` | Pull tous les kinds de toutes les features + taxonomy. |
| `--check` | Audit only — flag dirty, pas de pull. |

## Outputs

- `.snap/PRDs/{slug}.md` rafraîchis (si kind=prd).
- `.snap/designs/{slug}/...`, `.snap/wireframes/{slug}/...` (si design/wireframe).
- `.snap/tickets/{slug}.json` (si tickets — uniquement si tracker config).
- `manifests/{slug}.manifest.json.refs.{kind}.synced_at` mis à jour.
- `manifests/_taxonomy.json` mis à jour (workspace + domains + journeys).

## Failure handling

- Pas de ref dans manifest pour le kind demandé → ERROR + skip (rien à fetch).
- MCP indispo → log + sync_status="error" sur le ref.
- Tickets sans tracker → BLOCK (tickets kind nécessite `tickets.platform != none`).

## Suggest next

Après fetch :
- Édite localement (`.snap/PRDs/{slug}.md`).
- Push retour avec un skill métier (`/snap:define --refresh`, etc.) ou directement
  `bash skills/_shared/sync-push.sh ack ...` après push manuel.

## How to run a step

Lis `step-00-resolve.md`, suis, saute au `next_step` frontmatter, jusqu'au step terminal.
