---
step: 01-load
next_step: 02-decompose
description: Ensure PRD staging present (fetch from remote if needed), parse AC/scope/wireframes into context.
---

# step-01 — load

Read the feature PRD and stage its content for decomposition. PRD remote =
source of truth (set in `manifest.refs.prd`) ; local staging is rehydrated on
demand.

## Tasks

1. **Ensure PRD staging present** — if `.snap/PRDs/${feature_id}.md` is missing
   (it was trashed by `sync-push.sh ack` in `/snap:define` step-05), re-pull
   from remote :

   ```bash
   PRD_STAGING=$(bash skills/_shared/sync-push.sh staging-path \
     --feature-id="$feature_id" --kind=prd --project-root="$PWD")
   if [ ! -f "$PRD_STAGING" ]; then
     plan_json=$(bash skills/_shared/sync-fetch.sh plan \
       --feature-id="$feature_id" --kind=prd --project-root="$PWD")
     rc=$?
     [ "$rc" -ne 0 ] && {
       echo "ERROR: manifest has no refs.prd — run /snap:define first" >&2
       exit 1
     }
     PRD_URL=$(jq -r '.ref.url'      <<<"$plan_json")
     PRD_PAGE=$(jq -r '.ref.page_id // ""' <<<"$plan_json")
     PLATFORM=$(jq -r '.ref.platform' <<<"$plan_json")

     # Pull via docs-adapter (model executes MCP, writes to /tmp/prd-${feature_id}.md)
     bash skills/_shared/docs-adapter.sh \
       --action=get-page-content \
       --platform="$PLATFORM" \
       --page-id="$PRD_PAGE" \
       --out=/tmp/prd-"$feature_id".md

     bash skills/_shared/sync-fetch.sh ack \
       --feature-id="$feature_id" --kind=prd \
       --content-file=/tmp/prd-"$feature_id".md \
       --platform="$PLATFORM" --url="$PRD_URL" --page-id="$PRD_PAGE" \
       --project-root="$PWD"
   fi
   ```

2. **Read `${PRD_STAGING}`** and validate it has the sections required by
   `templates/docs-defaults/prd-feature.md` :
   - Problem
   - Solution overview
   - Acceptance criteria (AC-N format)
   - In scope / Out of scope
   - Wireframe references (optional)

   If a required section is missing, surface a parse error with the section
   name and abort via `progress.sh step --status=fail`.

3. **Extract structured data** into a working JSON kept in context (no file
   write yet) :
   ```json
   {
     "feature_id": "01-auth",
     "feature_title": "...",
     "problem": "...",
     "solution_overview": "...",
     "acceptance_criteria": [
       {"ac_id": "1", "ac_text": "..."}
     ],
     "in_scope": "...",
     "out_of_scope": "...",
     "wireframes": ["screen-id-1", "screen-id-2"]
   }
   ```

   Use `awk` or `sed` to slice between `## ` headings; do not write the JSON to
   disk.

4. **Read manifest** for the feature; remember `refs.prd.url` /
   `refs.prd.page_id` (linked from each ticket body — "Spec : <url>") and
   `refs.tickets.sync_status` (used to detect re-runs).

5. **Cross-reference wireframes** : if `refs.wireframes_gallery` is set on the
   manifest, capture the URL/IDs for inclusion in the ticket body. Wireframe
   staging files are not required at this step.

6. **Append progress** :
   ```bash
   bash skills/_shared/progress.sh step \
     --project-root="$PWD" \
     --skill=ticket \
     --feature-id="$feature_id" \
     --step-num=01 \
     --step-name=load \
     --status=ok
   ```

## Acceptance check

- `${PRD_STAGING}` exists and parses cleanly.
- `acceptance_criteria` array has ≥ 1 entry.

## Next step

→ `step-02-decompose.md`
