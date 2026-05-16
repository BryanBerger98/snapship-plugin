---
step: 01-fetch
next_step: 02-write
description: Pull contenu remote via MCP (docs-adapter pour PRDs/galleries, figma-helper pour design files, tickets-adapter pour tickets).
---

# step-01 — fetch from remote via MCP

## Tâches

1. **Lit `.snap/.fetch-plan.json`**, itère sur `targets[]`.

2. **Pour chaque target**, choisir l'adapter selon `kind` :

   | Kind | Adapter | Action |
   |---|---|---|
   | `prd`                 | `docs-adapter.sh`     | `get --page-id=...` |
   | `design_gallery`      | `docs-adapter.sh`     | `get --page-id=...` |
   | `wireframes_gallery`  | `docs-adapter.sh`     | `get --page-id=...` |
   | `tickets`             | `tickets-adapter.sh`  | `list --project-id=...` |
   | `design_file`         | `figma-helper.sh` / `penpot-helper.sh` | `get-design-context` |

3. **Lance via descripteur MCP** :
   ```bash
   bash skills/_shared/docs-adapter.sh --action=get --page-id="$PAGE_ID"
   # → exit 10 + descriptor JSON → orchestre MCP call → récupère content
   ```
   Stocke la réponse dans `.snap/.fetch-cache/{story_id}-{kind}.content`
   (ephémère).

4. **Sur erreur MCP** :
   - `bash skills/_shared/sync-fetch.sh fail --story-id=$FID --kind=$KIND --note="$ERR"`
   - Continue les autres targets (best-effort).

5. **Refresh taxonomy** (si `--all` + workspace.root_page_id défini) :
   - Re-pull root page + enfants (domains, journeys) via `docs-adapter.sh get`.
   - Update `manifests/_taxonomy.json` directement (pas via sync-fetch).

6. **Telemetry + progress** :
   ```bash
   bash skills/_shared/telemetry.sh log --skill=fetch --step-num=01 --step-name=fetch --status=ok \
     --extra="$(jq -nc --argjson n $N '{targets:$n}')"
   bash skills/_shared/progress.sh step --skill=fetch --story-id=_global \
     --step-num=01 --step-name=fetch --status=ok
   ```

## Continue à

`step-02-write.md`.
