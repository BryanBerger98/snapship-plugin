---
step: 01b-epic-ship
next_step: null
terminal: true
description: Epic-ship mode (v1.2) — fetch Epic + children live, generate top-level product section on doc platform when all children are done. Idempotent via content hash.
---

# step-01b — Epic ship section

Entered when `/snap:doc-update --epic=<platform_id>` is invoked. Skips feature
manifest path entirely — the Epic ticket on the tracker is the single source
of truth (v1.2 decision 3).

## Tasks

1. **Load config + resolve platform** :
   ```bash
   CONFIG_JSON=$(bash skills/_shared/load-config.sh --project-root="$PWD")
   PLATFORM=$(jq -r '.documentation.platform // "none"' <<<"$CONFIG_JSON")
   [ "$PLATFORM" = "none" ] && {
     echo "NOTICE: documentation.platform=none — skip Epic ship section"
     exit 0
   }
   case "$PLATFORM" in
     affine|notion) ;;
     *) echo "ERROR: unsupported documentation.platform=$PLATFORM" >&2; exit 1 ;;
   esac
   ```

2. **Fetch Epic live** :
   ```bash
   epic_json=$(bash skills/_shared/tickets-adapter.sh \
     --action=get --ticket-id="$EPIC_ID") || {
     echo "ERROR: failed to fetch Epic $EPIC_ID from tracker" >&2
     exit 1
   }
   story_type=$(jq -r '.story_type // ""' <<<"$epic_json")
   if [ "$story_type" != "epic" ]; then
     echo "ERROR: ticket $EPIC_ID is not an Epic (story_type=$story_type)" >&2
     echo "       --epic= expects an Epic platform_id." >&2
     exit 1
   fi
   ```

3. **List children + check all-done** :
   ```bash
   children_json=$(bash skills/_shared/tickets-adapter.sh \
     --action=list-children --ticket-id="$EPIC_ID") || {
     echo "ERROR: failed to list children of Epic $EPIC_ID" >&2
     exit 1
   }
   total=$(jq '.items | length' <<<"$children_json")
   if [ "$total" -eq 0 ]; then
     echo "NOTICE: Epic $EPIC_ID has no children — skip"
     exit 0
   fi
   done_count=$(jq '[.items[] | select(.state == "done" or .state == "closed")] | length' <<<"$children_json")
   if [ "$done_count" -lt "$total" ]; then
     echo "NOTICE: Epic $EPIC_ID: $done_count/$total US shipped — waiting completion"
     bash skills/_shared/progress.sh step --skill=doc-update \
       --story-id="epic-$EPIC_ID" --step-num=01b --step-name=epic-ship \
       --status=skip --note="$done_count/$total done"
     exit 0
   fi
   ```

   `list-children` is added to `tickets-adapter.sh` in v1.2 — returns
   `{items:[{platform_id,title,state,url,story_type}], count}`.

4. **Build content hash** (idempotence) :
   ```bash
   content_payload=$(jq -nc --argjson epic "$epic_json" --argjson kids "$children_json" \
     '{epic_id:$epic.platform_id, title:$epic.title,
       business_goal:($epic.business_goal // ""),
       success_metrics:($epic.success_metrics // []),
       children:($kids.items | map({platform_id,title,url}))}')
   content_hash=$(printf '%s' "$content_payload" | sha256sum | cut -d" " -f1)
   ```

5. **Skip if hash already present** :
   The Epic ticket body (or the doc page) carries a marker
   `<!-- snap:ship-hash:HASH -->`. If the marker matches `$content_hash`, the
   section is already published — exit with `skip` :
   ```bash
   existing_hash=$(printf '%s' "$epic_json" | jq -r '.body // ""' \
     | grep -oE 'snap:ship-hash:[a-f0-9]+' | cut -d: -f3 | head -1)
   if [ "$existing_hash" = "$content_hash" ]; then
     echo "Epic $EPIC_ID ship section already published (hash match) — skip"
     bash skills/_shared/progress.sh step --skill=doc-update \
       --story-id="epic-$EPIC_ID" --step-num=01b --step-name=epic-ship \
       --status=skip --note="hash $content_hash already present"
     exit 0
   fi
   ```

6. **Generate Markdown section** :
   ```markdown
   ## {{ epic.title }} (shipped)

   {{ epic.description }}

   **Business goal** : {{ epic.business_goal }}

   **Success metrics**
   - {{ metric_1 }}
   - {{ metric_2 }}

   **Shipped user stories**
   - [{{ child.title }}]({{ child.url }}) — {{ child.summary_one_line }}
   ```

   AI step — model emits the rendered markdown to
   `/tmp/epic-${EPIC_ID}-ship.md`.

7. **Append on doc platform** (skip if `--dry-run`) :
   ```bash
   if [ "$DRY_RUN" = "true" ]; then
     echo "DRY: would append Epic ship section to documentation platform"
   else
     bash skills/_shared/docs-adapter.sh \
       --action=append-section --platform="$PLATFORM" \
       --target=epic-ship --epic-id="$EPIC_ID" \
       --content-file=/tmp/epic-${EPIC_ID}-ship.md \
       --marker-hash="$content_hash"
   fi
   ```

8. **Stamp Epic ticket body** with marker (idempotence anchor) :
   ```bash
   if [ "$DRY_RUN" != "true" ]; then
     bash skills/_shared/tickets-adapter.sh --action=update \
       --ticket-id="$EPIC_ID" \
       --body="$(jq -r '.body' <<<"$epic_json")
<!-- snap:ship-hash:$content_hash -->"
   fi
   ```

9. **Telemetry + progress** :
   ```bash
   bash skills/_shared/telemetry.sh log \
     --project-root="$PWD" --skill=doc-update \
     --step-num=01b --step-name=epic-ship --status=ok \
     --extra="$(jq -nc --arg eid "$EPIC_ID" --arg n "$total" '{epic_id:$eid, children:$n|tonumber}')"

   bash skills/_shared/progress.sh step \
     --project-root="$PWD" --skill=doc-update \
     --story-id="epic-$EPIC_ID" --step-num=01b \
     --step-name=epic-ship --status=ok
   bash skills/_shared/progress.sh finish \
     --project-root="$PWD" --skill=doc-update \
     --story-id="epic-$EPIC_ID" --status=ok
   ```

## Acceptance check

- Epic fetched (`story_type == epic`).
- All children `state == done|closed` on tracker.
- Section generated and pushed (or marked skip on `--dry-run`).
- Content hash recorded on Epic ticket body (idempotence anchor).

## Terminal

This step is terminal for `--epic=` mode. Feature mode continues to
`step-01-collect.md`.
