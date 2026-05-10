---
step: 05-publish
description: Push per-feature PRDs as immutable archive pages under {prd_root}/{YYYY}/{MM-YYYY}/{NN-feature}; tag with domains; ensure domain + journey pages exist (idempotent). Cache IDs in meta.json + domains.json. Terminal step.
---

# step-05 — publish (v0.2)

Final step. Three responsibilities:

1. **PRD archive** — create one immutable page per feature under
   `{prd_root}/{YYYY}/{MM-YYYY}/{NN-feature}`, tagged with impacted domains.
2. **Functional doc skeleton** — idempotent `lookup-or-create-page` for every
   domain + impacted journey referenced by features. New journey pages start
   empty; they are populated by `/snap:doc-update` post-ship.
3. **Cache** — persist page IDs to `meta.json` (`prd` object) and
   `domains.json` (domain + journey entries).

This step has **no** `next_step` — terminal.

## Inputs

- `.claude/product/features/{feature_id}/prd-feature.md` (one per feature)
- `.claude/product/features/{feature_id}/meta.json` (state=`defined`)
- `.claude/product/.config-resolved.json` → `documentation.platform`,
  `documentation.paths.{functional_root,prd_root}`
- `.claude/product/domains.json` (cache of existing domain/journey page IDs)

## Tasks

### A. Skip if platform = none

```bash
PLATFORM=$(jq -r '.documentation.platform // "none"' .claude/product/.config-resolved.json)
```

If `$PLATFORM == "none"` → log notice, mark progress `skip`, stop.
If `$PLATFORM ∉ {affine, notion}` → abort with error pointing to `/snap:init`.

### B. Read v0.2 paths

```bash
FUNCTIONAL_ROOT=$(jq -r '.documentation.paths.functional_root' .claude/product/.config-resolved.json)
PRD_ROOT=$(jq -r '.documentation.paths.prd_root' .claude/product/.config-resolved.json)
WORKSPACE_ID=$(jq -r '.documentation.workspace.id // ""' .claude/product/.config-resolved.json)

YEAR=$(date -u +%Y)
MONTH_YEAR=$(date -u +%m-%Y)
```

Both roots are guaranteed non-empty when `$PLATFORM != "none"` (load-config
injects defaults).

### C. Per feature — main loop

For each `feature_id` under `.claude/product/features/`:

1. **Skip if already published** (idempotent re-run):
   ```bash
   PRD_PAGE_ID=$(jq -r '.prd.page_id // ""' "features/$fid/meta.json")
   if [ -n "$PRD_PAGE_ID" ]; then
     echo "skip $fid (already published, prd.page_id=$PRD_PAGE_ID)"
     continue
   fi
   ```

2. **Compute PRD path + tags**:
   ```bash
   PRD_PATH="${PRD_ROOT}/${YEAR}/${MONTH_YEAR}/${fid}"
   DOMAINS_JSON=$(jq -c '.domains // []' "features/$fid/meta.json")
   ```

3. **Create PRD parent path** (idempotent recursive):
   ```bash
   bash skills/_shared/docs-adapter.sh \
     --action=create-page-tree \
     --platform="$PLATFORM" \
     --workspace-id="$WORKSPACE_ID" \
     --path="${PRD_ROOT}/${YEAR}/${MONTH_YEAR}"
   ```
   Maps to MCP — model executes, captures leaf `page_id` as `$MONTH_PARENT_ID`.

4. **Create the PRD page** (always new — `feature_id` is unique):
   ```bash
   bash skills/_shared/docs-adapter.sh \
     --action=create \
     --platform="$PLATFORM" \
     --parent-id="$MONTH_PARENT_ID" \
     --title="$(jq -r .feature_name features/$fid/meta.json)" \
     --content-file="features/$fid/prd-feature.md"
   ```
   Capture `page_id` + `url` from MCP response → `$PRD_PAGE_ID`, `$PRD_URL`.

5. **Tag the PRD page with impacted domains**:
   ```bash
   bash skills/_shared/docs-adapter.sh \
     --action=set-page-tags \
     --platform="$PLATFORM" \
     --page-id="$PRD_PAGE_ID" \
     --tags="$DOMAINS_JSON"
   ```

6. **Lookup-or-create domain pages** (idempotent):
   ```bash
   FROOT_ID=$(bash skills/_shared/docs-adapter.sh \
     --action=lookup-or-create-page \
     --platform="$PLATFORM" \
     --workspace-id="$WORKSPACE_ID" \
     --title="$FUNCTIONAL_ROOT")  # → page_id captured by model

   for domain in $(echo "$DOMAINS_JSON" | jq -r '.[]'); do
     # Check cache first
     existing=$(bash skills/_shared/domains-state.sh get-domain "$domain" --project-root="$PWD")
     if [ -z "$existing" ]; then
       # Create under functional root; user-provided title comes from state file
       DOMAIN_TITLE=$(...)  # from define-state phase B step 7
       bash skills/_shared/docs-adapter.sh \
         --action=lookup-or-create-page \
         --platform="$PLATFORM" \
         --parent-id="$FROOT_ID" \
         --title="$DOMAIN_TITLE"
       # capture $DOMAIN_PAGE_ID, $DOMAIN_URL from MCP response

       bash skills/_shared/domains-state.sh add-domain \
         "$domain" "$DOMAIN_TITLE" "$DOMAIN_PAGE_ID" "$DOMAIN_URL" \
         --project-root="$PWD"
     fi
   done
   ```

7. **Lookup-or-create journey pages** (idempotent):
   ```bash
   for entry in $(jq -c '.impacted_journeys[]' "features/$fid/meta.json"); do
     domain=$(echo "$entry" | jq -r '.domain')
     jslug=$(echo "$entry" | jq -r '.journey_slug')
     jtitle=$(echo "$entry" | jq -r '.journey_title')
     is_new=$(echo "$entry" | jq -r '.is_new // false')

     existing=$(bash skills/_shared/domains-state.sh get-journey "$domain" "$jslug" --project-root="$PWD")
     if [ -z "$existing" ]; then
       DOMAIN_PARENT_ID=$(bash skills/_shared/domains-state.sh get-domain "$domain" --project-root="$PWD" | jq -r '.domain_page_id')

       bash skills/_shared/docs-adapter.sh \
         --action=lookup-or-create-page \
         --platform="$PLATFORM" \
         --parent-id="$DOMAIN_PARENT_ID" \
         --title="$jtitle"
       # capture $JOURNEY_PAGE_ID, $JOURNEY_URL

       bash skills/_shared/domains-state.sh add-journey \
         "$domain" "$jslug" "$jtitle" "$JOURNEY_PAGE_ID" "$JOURNEY_URL" \
         --project-root="$PWD"
     fi
   done
   ```

   New journey pages are intentionally **empty** — `/snap:doc-update` populates
   them after `/snap:qa` validates the feature.

8. **Update `meta.json`** with `prd` object:
   ```bash
   tmp=$(mktemp)
   jq --arg pid "$PRD_PAGE_ID" \
      --arg url "$PRD_URL" \
      --arg path "$PRD_PATH" \
      --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '.prd = {page_id: $pid, url: $url, path: $path}
       | .updated_at = $ts' \
      "features/$fid/meta.json" > "$tmp" && mv "$tmp" "features/$fid/meta.json"
   ```

9. **Validate `meta.json` against schema after each mutation**:
   ```bash
   ajv validate \
     -s skills/_shared/schemas/meta.schema.json \
     -d "features/$fid/meta.json" \
     --spec=draft2020 --strict=false
   ```
   On failure, revert via the prior `tmp` and surface error. Do not advance.

### D. Telemetry

```bash
bash skills/_shared/telemetry.sh append \
  --project-root="$PWD" \
  --skill=define \
  --status=ok \
  --extra="{\"features\":$N, \"platform\":\"$PLATFORM\", \"v\":\"0.2\"}"
```

### E. Progress

```bash
bash skills/_shared/update-progress.sh \
  --project-root="$PWD" \
  --feature-id=_global \
  --step-num=05 \
  --step-name=publish \
  --status=ok \
  --skill=define
```

### F. Cleanup

```bash
bash skills/_shared/define-state.sh wipe --project-root="$PWD"
```

`domains.json` is **persistent** — keep it.

## Failure handling

- **MCP error mid-loop** (auth, rate limit, conflict): retry once with backoff.
  On second failure, mark progress `fail` for that `feature_id`, leave its
  `meta.json` un-updated (prd.page_id absent → re-run skips others, retries
  this one).
- **Schema validation failure on `meta.json`**: revert mutation, mark progress
  `fail`, stop (do not continue with remaining features — bug not transient).
- **Mid-loop partial success**: `/snap:define --resume` re-enters this step
  and skips features whose `prd.page_id` is already set.

## What this step does NOT do

- ❌ Push a "global PRD" page (v0.1 concept dropped — see `docs/decisions.md`).
- ❌ Modify domain pages with a "modification log" entry (would bloat).
- ❌ Link journey ↔ PRD (journey is a clean spec; PRD = external archive).
- ❌ Populate journey body for new journeys (deferred to `/snap:doc-update`).

## Acceptance check

- Each feature has `prd.page_id`, `prd.url`, `prd.path` in `meta.json` (or
  platform=none).
- `domains.json` contains every domain + journey referenced by features.
- `progress.md` ends with `define step-05 publish — ok` (or `skip`).

## Next step

_None — terminal step._
