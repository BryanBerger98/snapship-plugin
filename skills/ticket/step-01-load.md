---
step: 01-load
next_step: 02-decompose
description: Load PRD + live tracker context (Epics, milestones, versions) into ephemeral cache. `--standalone` skips PRD load.
---

# step-01 — load

Read the feature PRD (skipped under `--standalone`) and snapshot the live
tracker context (Epics, milestones, versions) into the ephemeral subject
cache. **No persistent local cache of tracker state** (decision #3) — every
run fetches fresh.

## Tasks

### A. Standalone short-circuit (v1.2)

If `--standalone` was set in step-00, skip subtasks 1-5 (PRD load) entirely
and jump directly to **B. Live tracker fetch**. The raw user input collected
at step-02 will be the only source of draft material.

### B. Live tracker fetch (always — decision #3)

Snapshot tracker context into the ephemeral subject cache so downstream steps
(03b hierarchy clustering, 03c metadata, 05 push) operate on a frozen view.

```bash
# Capabilities first — gates which list-* calls are valid.
caps=$(bash skills/_shared/tickets-adapter.sh \
  --action=capabilities --platform="$platform")

# Epics — always supported (every tracker has the concept).
epics=$(bash skills/_shared/tickets-adapter.sh \
  --action=list-epics --platform="$platform")

milestones="[]"
if [ "$(jq -r '.supports_milestone' <<<"$caps")" = "true" ]; then
  milestones=$(bash skills/_shared/tickets-adapter.sh \
    --action=list-milestones --platform="$platform")
fi

versions="[]"
if [ "$(jq -r '.supports_version' <<<"$caps")" = "true" ]; then
  versions=$(bash skills/_shared/tickets-adapter.sh \
    --action=list-versions --platform="$platform")
fi

# Perf signal — > 50 Epics fetched warns the user (large trackers slow
# clustering at step-03b).
epic_count=$(jq 'length' <<<"$epics")
[ "$epic_count" -gt 50 ] && \
  echo "WARN: $epic_count Epics fetched — hierarchy clustering may be slow." >&2

# Persist into ephemeral cache for downstream steps.
jq -n --argjson c "$caps" --argjson e "$epics" \
      --argjson m "$milestones" --argjson v "$versions" \
      '{capabilities:$c, epics:$e, milestones:$m, versions:$v,
        fetched_at:(now|todate)}' \
  | bash skills/_shared/cache-runtime.sh write "$SUBJECT_ID" \
      tracker-context.json --project-root="$PWD"
```

Network failure on `list-*` is fatal for hierarchy mode (we can't propose
clustering without the Epic list), but tolerable for `--standalone --auto`
flows that emit only leaf tickets — let `tickets-adapter.sh` surface the
retry-exhausted error and let the trap purge the subject on exit.

### C. PRD load (normal mode only)

1. **Ensure PRD staging present** — if `.snap/PRDs/${story_id}.md` is missing
   (it was trashed by `sync-push.sh ack` in `/snap:define` step-05), re-pull
   from remote :

   ```bash
   PRD_STAGING=$(bash skills/_shared/sync-push.sh staging-path \
     --story-id="$story_id" --kind=prd --project-root="$PWD")
   if [ ! -f "$PRD_STAGING" ]; then
     plan_json=$(bash skills/_shared/sync-fetch.sh plan \
       --story-id="$story_id" --kind=prd --project-root="$PWD")
     rc=$?
     [ "$rc" -ne 0 ] && {
       echo "ERROR: manifest has no refs.prd — run /snap:define first" >&2
       exit 1
     }
     PRD_URL=$(jq -r '.ref.url'      <<<"$plan_json")
     PRD_PAGE=$(jq -r '.ref.page_id // ""' <<<"$plan_json")
     PLATFORM=$(jq -r '.ref.platform' <<<"$plan_json")

     # Pull via docs-adapter (model executes MCP, writes to /tmp/prd-${story_id}.md)
     bash skills/_shared/docs-adapter.sh \
       --action=get-page-content \
       --platform="$PLATFORM" \
       --page-id="$PRD_PAGE" \
       --out=/tmp/prd-"$story_id".md

     bash skills/_shared/sync-fetch.sh ack \
       --story-id="$story_id" --kind=prd \
       --content-file=/tmp/prd-"$story_id".md \
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
     "story_id": "01-auth",
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
     --story-id="$story_id" \
     --step-num=01 \
     --step-name=load \
     --status=ok
   ```

## Acceptance check

- `.snap/.runtime/<SUBJECT_ID>/tracker-context.json` exists and contains
  `capabilities`, `epics`, `milestones`, `versions`, `fetched_at`.
- Normal mode (non-`--standalone`) :
  - `${PRD_STAGING}` exists and parses cleanly.
  - `acceptance_criteria` array has ≥ 1 entry.

## Next step

→ `step-02-decompose.md`
