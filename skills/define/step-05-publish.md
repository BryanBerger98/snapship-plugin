---
step: 05-publish
description: Push PRD pages to {prd_root}/{YYYY}/{MM-YYYY}/{NN-feature}; tag with domains; ensure domain + journey pages exist (idempotent). Ack refs into manifests via sync-push.sh; cache page IDs in _taxonomy.json. Trash PRD staging on ack. Terminal step.
---

# step-05 — publish

Final step. Three responsibilities :

1. **PRD archive** — create one immutable page per feature under
   `{prd_root}/{YYYY}/{MM-YYYY}/{NN-feature}`, tagged with impacted domains.
2. **Functional doc skeleton** — idempotent `lookup-or-create-page` for every
   domain + impacted journey referenced by features. New journey pages start
   empty; populated by `/snap:doc-update` post-ship.
3. **Sync refs** — ack the PRD push into the manifest via `sync-push.sh ack`
   (trashes staging file, updates `refs.prd`). Persist domain + journey page
   IDs to `_taxonomy.json` via `taxonomy-state.sh`.

Terminal step — no `next_step`.

## Inputs

- `.snap/PRDs/{fid}.md` (staging — trashed on ack)
- `.snap/manifests/{fid}.manifest.json` (state=`defined`)
- `CONFIG_JSON` shell var (from step-00) → `documentation.platform`,
  `documentation.paths.{functional_root,prd_root}`, `documentation.workspace.id`.
- `.snap/manifests/_taxonomy.json` (cache of domain + journey page IDs)

## Tasks

### A. Skip if platform = none

```bash
PLATFORM=$(jq -r '.documentation.platform // "none"' <<<"$CONFIG_JSON")
```

- `$PLATFORM == "none"` → log notice, mark `progress.sh step --status=skip`, stop.
- `$PLATFORM ∉ {affine, notion}` → abort with error pointing to `/snap:init`.

### B. Read paths

```bash
FUNCTIONAL_ROOT=$(jq -r '.documentation.paths.functional_root' <<<"$CONFIG_JSON")
PRD_ROOT=$(jq -r '.documentation.paths.prd_root' <<<"$CONFIG_JSON")
WORKSPACE_ID=$(jq -r '.documentation.workspace.id // ""' <<<"$CONFIG_JSON")

YEAR=$(date -u +%Y)
MONTH_YEAR=$(date -u +%m-%Y)
```

Both roots are guaranteed non-empty when `$PLATFORM != "none"` (load-config
injects defaults).

### C. Per feature — main loop

For each manifest in `.snap/manifests/*.manifest.json` (skip `_taxonomy.json`) :

```bash
fid=$(jq -r '.story_id' "$MANIFEST")
```

1. **Skip if already synced** (idempotent re-run) :
   ```bash
   PRD_STATUS=$(jq -r '.refs.prd.sync_status // ""' "$MANIFEST")
   if [ "$PRD_STATUS" = "synced" ]; then
     echo "skip $fid (refs.prd.sync_status=synced)"
     continue
   fi
   ```

2. **Compute path + tags** :
   ```bash
   PRD_PATH="${PRD_ROOT}/${YEAR}/${MONTH_YEAR}/${fid}"
   DOMAINS_JSON=$(jq -c '.domains // []' "$MANIFEST")
   ```

3. **Create PRD parent path** (idempotent recursive) :
   ```bash
   bash skills/_shared/docs-adapter.sh \
     --action=create-page-tree \
     --platform="$PLATFORM" \
     --workspace-id="$WORKSPACE_ID" \
     --path="${PRD_ROOT}/${YEAR}/${MONTH_YEAR}"
   ```
   Maps to MCP — model executes, captures leaf `page_id` as `$MONTH_PARENT_ID`.

4. **Create the PRD page** (always new — `story_id` is unique) :
   ```bash
   PRD_STAGING=$(bash skills/_shared/sync-push.sh staging-path \
     --story-id="$fid" --kind=prd --project-root="$PWD")
   bash skills/_shared/docs-adapter.sh \
     --action=create \
     --platform="$PLATFORM" \
     --parent-id="$MONTH_PARENT_ID" \
     --title="$(jq -r .story_name "$MANIFEST")" \
     --content-file="$PRD_STAGING"
   ```
   Capture `page_id` + `url` from MCP response → `$PRD_PAGE_ID`, `$PRD_URL`.

5. **Tag the PRD page with impacted domains** :
   ```bash
   bash skills/_shared/docs-adapter.sh \
     --action=set-page-tags \
     --platform="$PLATFORM" \
     --page-id="$PRD_PAGE_ID" \
     --tags="$DOMAINS_JSON"
   ```

6. **Lookup-or-create domain pages** (idempotent) :
   ```bash
   FROOT_ID=$(bash skills/_shared/docs-adapter.sh \
     --action=lookup-or-create-page \
     --platform="$PLATFORM" \
     --workspace-id="$WORKSPACE_ID" \
     --title="$FUNCTIONAL_ROOT")  # → page_id captured by model

   for domain in $(echo "$DOMAINS_JSON" | jq -r '.[]'); do
     existing=$(bash skills/_shared/taxonomy-state.sh get-domain "$domain" \
       --project-root="$PWD")
     if [ -z "$existing" ]; then
       DOMAIN_TITLE=$(jq -r --arg fid "$fid" --arg d "$domain" '
         .features[] | select(.story_id == $fid)
         | .impacted_journeys[] | select(.domain == $d)
         | .domain_title // $d
       ' .snap/.define-state.json | head -1)
       bash skills/_shared/docs-adapter.sh \
         --action=lookup-or-create-page \
         --platform="$PLATFORM" \
         --parent-id="$FROOT_ID" \
         --title="$DOMAIN_TITLE"
       # capture $DOMAIN_PAGE_ID, $DOMAIN_URL from MCP response

       bash skills/_shared/taxonomy-state.sh add-domain \
         "$domain" "$DOMAIN_TITLE" "$DOMAIN_PAGE_ID" "$DOMAIN_URL" \
         --project-root="$PWD"
     fi
   done
   ```

7. **Lookup-or-create journey pages** (idempotent) :
   ```bash
   for entry in $(jq -c '.impacted_journeys[]' "$MANIFEST"); do
     domain=$(echo "$entry" | jq -r '.domain')
     jslug=$(echo "$entry"  | jq -r '.journey_slug')
     jtitle=$(jq -r --arg fid "$fid" --arg d "$domain" --arg s "$jslug" '
       .features[] | select(.story_id == $fid)
       | .impacted_journeys[] | select(.domain == $d and .journey_slug == $s)
       | .journey_title // $s
     ' .snap/.define-state.json | head -1)

     existing=$(bash skills/_shared/taxonomy-state.sh get-journey \
       "$domain" "$jslug" --project-root="$PWD")
     if [ -z "$existing" ]; then
       DOMAIN_PARENT_ID=$(bash skills/_shared/taxonomy-state.sh get-domain "$domain" \
         --project-root="$PWD" | jq -r '.page_id')

       bash skills/_shared/docs-adapter.sh \
         --action=lookup-or-create-page \
         --platform="$PLATFORM" \
         --parent-id="$DOMAIN_PARENT_ID" \
         --title="$jtitle"
       # capture $JOURNEY_PAGE_ID, $JOURNEY_URL

       bash skills/_shared/taxonomy-state.sh add-journey \
         "$domain" "$jslug" "$jtitle" "$JOURNEY_PAGE_ID" "$JOURNEY_URL" \
         --project-root="$PWD"
     fi
   done
   ```

   New journey pages are intentionally **empty** — `/snap:doc-update` populates
   them after `/snap:qa` validates the feature.

8. **Ack PRD push** — updates `manifest.refs.prd` and trashes the staging file
   in one atomic helper call :
   ```bash
   bash skills/_shared/sync-push.sh ack \
     --project-root="$PWD" \
     --story-id="$fid" \
     --kind=prd \
     --platform="$PLATFORM" \
     --url="$PRD_URL" \
     --page-id="$PRD_PAGE_ID"
   ```
   Sets `refs.prd = { platform, url, page_id, synced_at, sync_status: "synced" }`
   and trashes `.snap/PRDs/{fid}.md` (cf. core philosophy : remote = source of
   truth, local staging only).

9. **Validate manifest after ack** :
   ```bash
   ajv validate \
     -s skills/_shared/schemas/manifest.schema.json \
     -d ".snap/manifests/${fid}.manifest.json" \
     --spec=draft2020 --strict=false
   ```
   On failure, mark `refs.prd.sync_status=error` via `sync-push.sh fail` and
   stop (bug, not transient).

### D. Telemetry

```bash
bash skills/_shared/telemetry.sh log \
  --project-root="$PWD" \
  --skill=define \
  --step-num=05 \
  --step-name=publish \
  --status=ok \
  --extra="{\"features\":$N, \"platform\":\"$PLATFORM\"}"
```

### E. Progress

```bash
bash skills/_shared/progress.sh step \
  --project-root="$PWD" \
  --skill=define \
  --story-id=_global \
  --step-num=05 \
  --step-name=publish \
  --status=ok

bash skills/_shared/progress.sh finish \
  --project-root="$PWD" \
  --skill=define \
  --story-id=_global \
  --status=ok
```

### F. Cleanup transient state

```bash
bash skills/_shared/define-state.sh wipe --project-root="$PWD"
```

`_taxonomy.json` is **persistent** — keep it.

## Failure handling

- **MCP error mid-loop** (auth, rate limit, conflict) : retry once with backoff.
  On second failure, call `sync-push.sh fail --kind=prd --story-id="$fid"`
  (sets `refs.prd.sync_status=error`, keeps staging), then `progress.sh step
  --status=fail`. Re-run skips features whose `refs.prd.sync_status=synced` and
  retries the failed one.
- **Schema validation failure on manifest** : mark `refs.prd.sync_status=error`,
  `progress.sh step --status=fail`, stop (do not continue — bug not transient).
- **Mid-loop partial success** : `/snap:define --resume` re-enters step-05 and
  skips features already synced.

## What this step does NOT do

- ❌ Push a "global PRD" page (v0.1 concept dropped — see `docs/contributing/decisions.md`).
- ❌ Modify domain pages with a "modification log" entry (would bloat).
- ❌ Link journey ↔ PRD (journey is a clean spec; PRD = external archive).
- ❌ Populate journey body for new journeys (deferred to `/snap:doc-update`).
- ❌ Keep PRD staging file after ack (trashed by `sync-push.sh ack`).

## Acceptance check

- Each manifest has `refs.prd.{platform, url, page_id, synced_at,
  sync_status:"synced"}` (or `$PLATFORM == "none"` → step skipped entirely).
- `_taxonomy.json` contains every domain + journey referenced by features.
- `.snap/PRDs/{fid}.md` files all trashed after successful ack.
- `progress.json.in_flight` no longer contains a `define` entry for `_global`
  (purged by `progress.sh finish --status=ok`).

## Next step

_None — terminal step._
