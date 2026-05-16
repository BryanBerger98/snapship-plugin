---
step: 01-fetch
next_step: 02-write
description: Pull contenu remote via MCP (docs-adapter pour PRDs/galleries, figma-helper pour design files, tickets-adapter pour tickets).
---

# step-01 — fetch from remote via MCP

## Tâches

1. **Lit `.snap/.fetch-plan.json`**.

2. **Probe-tracker branche** (si `mode == "probe-tracker"`) :
   ```bash
   plan_mode=$(jq -r '.mode' .snap/.fetch-plan.json)
   if [ "$plan_mode" = "probe-tracker" ]; then
     # Connectivity + auth + capability refresh en un seul call : capabilities
     # est l'endpoint le plus léger et tolère un read-only token.
     caps_json=$(bash skills/_shared/tickets-adapter.sh \
       --action=capabilities 2>&1) || {
       echo "ERROR: tracker probe failed — connectivity or auth issue" >&2
       echo "$caps_json" >&2
       exit 1
     }
     # Validate JSON shape ; reject HTML/error payloads.
     if ! jq -e '.platform and (.supports_epic | type == "boolean")' <<<"$caps_json" >/dev/null 2>&1; then
       echo "ERROR: tracker probe returned malformed capability payload" >&2
       echo "$caps_json" >&2
       exit 1
     fi
     # Cache run-scope
     mkdir -p .snap/.runtime
     printf '%s' "$caps_json" > .snap/.runtime/tracker-capabilities.json
     echo "OK: tracker probe — $(jq -r '.platform' <<<"$caps_json") reachable, capabilities cached"
     bash skills/_shared/telemetry.sh log --skill=fetch \
       --step-num=01 --step-name=probe-tracker --status=ok
     bash skills/_shared/progress.sh step --skill=fetch --story-id=_global \
       --step-num=01 --step-name=probe-tracker --status=ok
     exit 0   # short-circuits step-02/03 (no staging writes for probe mode)
   fi
   ```

3. **Itère sur `targets[]`** (mode fetch / check).

4. **Pour chaque target**, choisir l'adapter selon `kind` :

   | Kind | Adapter | Action |
   |---|---|---|
   | `prd`                 | `docs-adapter.sh`     | `get --page-id=...` |
   | `design_gallery`      | `docs-adapter.sh`     | `get --page-id=...` |
   | `wireframes_gallery`  | `docs-adapter.sh`     | `get --page-id=...` |
   | `design_file`         | `figma-helper.sh` / `penpot-helper.sh` | `get-design-context` |

   **`tickets` n'est plus un kind valide en v1.2** (drop décision 3).

5. **Lance via descripteur MCP** :
   ```bash
   bash skills/_shared/docs-adapter.sh --action=get --page-id="$PAGE_ID"
   # → exit 10 + descriptor JSON → orchestre MCP call → récupère content
   ```
   Stocke la réponse dans `.snap/.fetch-cache/{story_id}-{kind}.content`
   (ephémère).

6. **Sur erreur MCP** :
   - `bash skills/_shared/sync-fetch.sh fail --story-id=$FID --kind=$KIND --note="$ERR"`
   - Continue les autres targets (best-effort).

7. **Refresh taxonomy** (si `--all` + workspace.root_page_id défini) :
   - Re-pull root page + enfants (domains, journeys) via `docs-adapter.sh get`.
   - Update `manifests/_taxonomy.json` directement (pas via sync-fetch).

8. **Telemetry + progress** :
   ```bash
   bash skills/_shared/telemetry.sh log --skill=fetch --step-num=01 --step-name=fetch --status=ok \
     --extra="$(jq -nc --argjson n $N '{targets:$n}')"
   bash skills/_shared/progress.sh step --skill=fetch --story-id=_global \
     --step-num=01 --step-name=fetch --status=ok
   ```

## Continue à

`step-02-write.md`.
