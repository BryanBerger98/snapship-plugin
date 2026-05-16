---
name: fetch
description: Re-synchronise le local depuis les plateformes distantes (Notion/AFFiNE pour PRDs/galleries, Figma/Penpot pour design files). v1.2 — tickets ne sont plus cachés localement (tracker = source unique) ; `--probe-tracker` rafraîchit connectivity/auth/capabilities run-scope.
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, AskUserQuestion
---

# /snap:fetch — re-sync local depuis remote (v1.2)

Remote = source de vérité. Ce skill rapatrie le contenu distant dans le staging
local (`.snap/PRDs/`, `.snap/designs/`, etc.) pour édition ou refresh, et met à
jour `manifests/{slug}.manifest.json.refs.*.synced_at` + `sync_status=synced`.

**v1.2 breaking change** — `tickets` n'est plus un kind valide. Les tickets
vivent uniquement sur le tracker (décision 3, single source of truth). Pour
vérifier la santé du tracker côté plugin, utiliser `--probe-tracker`.

## Quand utiliser

- PRD modifié sur Notion/AFFiNE, on veut récupérer la dernière version locale.
- Avant un re-push (`/snap:define --refresh`), pour partir de la version remote.
- Après `/snap:upgrade`, pour absorber drift remote ↔ local.
- Désync detection : `/snap:fetch --check` flag manifests dont remote > local.
- Probe tracker : `/snap:fetch --probe-tracker` valide connectivity + auth +
  rafraîchit la capability cache run-scope (`.snap/.runtime/tracker-capabilities.json`).

## Pipeline

| # | Step | Purpose |
|---|------|---------|
| 00 | `step-00-resolve.md` | Parse args, résout features + kinds à fetch depuis manifests |
| 01 | `step-01-fetch.md`   | Pull contenu remote via docs-adapter / figma-helper / tickets-adapter |
| 02 | `step-02-write.md`   | Écrit staging files dans `.snap/PRDs/`, `designs/`, etc. |
| 03 | `step-03-update.md`  | Update manifest refs (synced_at + sync_status) |

## Args

```
/snap:fetch [--feature=SLUG] [--kind=prd|design|wireframe|all] [--all] [--check] [--probe-tracker] [--dry-run]
```

- `--feature=SLUG` : story_id ciblée (ex: `01-auth`). Sans, dépend de `--all`.
- `--kind=K` : type de ressource (défaut `all` si feature passée). Valeurs :
  `prd`, `design`, `wireframe`, `all`. **`tickets` retiré en v1.2** (tracker
  source unique).
- `--all` : toutes les features du workspace.
- `--check` : **opt-in désync detection**. Ne télécharge rien.
  Compare `manifests/*.refs.<kind>.synced_at` vs `last_edited_time` remote.
  Si remote > local → marque `sync_status="dirty"` et liste.
- `--probe-tracker` : ping tracker API + valide auth + rafraîchit
  `tracker_capabilities()` dans `.snap/.runtime/tracker-capabilities.json`
  (cache run-scope). Mutuellement exclusif avec `--feature` / `--all` / `--kind`.
- `--dry-run` : montre plan sans écrire.

## Combinaisons

| Args | Effet |
|---|---|
| `--feature=01-auth --kind=prd` | Pull PRD de 01-auth uniquement. |
| `--feature=01-auth --kind=all` | Pull tous les kinds de 01-auth (PRD/design/wireframe). |
| `--all` | Pull tous les kinds de toutes les features + taxonomy. |
| `--check` | Audit only — flag dirty, pas de pull. |
| `--probe-tracker` | Connectivity + auth + capabilities refresh (no file writes). |

## Outputs

- `.snap/PRDs/{slug}.md` rafraîchis (si kind=prd).
- `.snap/designs/{slug}/...`, `.snap/wireframes/{slug}/...` (si design/wireframe).
- `manifests/{slug}.manifest.json.refs.{kind}.synced_at` mis à jour.
- `manifests/_taxonomy.json` mis à jour (workspace + domains + journeys).
- `.snap/.runtime/tracker-capabilities.json` (si `--probe-tracker`).

**v1.2 — aucune écriture `.snap/tickets/`.** Les tickets sont lus en live via
`tickets-adapter.sh get-ticket` directement par les skills consommateurs (`/qa`,
`/develop`, `/doc-update`).

## Failure handling

- Pas de ref dans manifest pour le kind demandé → ERROR + skip (rien à fetch).
- MCP indispo → log + sync_status="error" sur le ref.
- `--probe-tracker` + tracker indispo / token invalide → exit 1 avec message
  d'erreur explicite (pas de fallback silencieux).

## Suggest next

Après fetch :
- Édite localement (`.snap/PRDs/{slug}.md`).
- Push retour avec un skill métier (`/snap:define --refresh`, etc.) ou directement
  `bash skills/_shared/sync-push.sh ack ...` après push manuel.

## How to run a step

Lis `step-00-resolve.md`, suis, saute au `next_step` frontmatter, jusqu'au step terminal.
