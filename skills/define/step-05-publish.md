---
step: 05-publish
description: Push PRD pages to {prd_root}/{YYYY}/{MM-YYYY}/{NN-feature}; tag with domains; ensure domain + journey pages exist (idempotent). Delegates the MCP sequence to the snap-publisher sub-agent. Terminal step.
---

# step-05 — publish

Final step. Three responsibilities :

1. **PRD archive** — create one immutable page per feature under
   `{prd_root}/{YYYY}/{MM-YYYY}/{NN-feature}`, tagged with impacted domains.
2. **Functional doc skeleton** — idempotent `lookup-or-create-page` for every
   domain + impacted journey referenced by features. New journey pages start
   empty ; populated by `/snap:doc-update` post-ship.
3. **Sync refs** — ack the PRD push into the manifest via `sync-push.sh ack`
   (trashes staging file, updates `refs.prd`). Persist domain + journey page
   IDs to `_taxonomy.json` via `taxonomy-state.sh`.

The MCP-heavy sequence (steps 1–8) is delegated to the **snap-publisher**
sub-agent — subprocesses can emit `docs-adapter.sh` descriptors but cannot
invoke MCP themselves. This step orchestrates : skip-check, brief build,
sub-agent dispatch, outcome parse, telemetry.

Terminal step — no `next_step`.

## Inputs

- `.snap/PRDs/{fid}.md` (staging — trashed on ack by sub-agent).
- `.snap/manifests/{fid}.manifest.json` (state=`defined`).
- `CONFIG_JSON` — **always re-loaded** from `snap.config.json` at step entry
  (config = single source of truth, never snapshotted) :
  ```bash
  CONFIG_JSON=$(bash skills/_shared/load-config.sh --project-root="$PWD")
  ```
  Read `documentation.platform`, `documentation.paths.{functional_root,prd_root}`,
  `documentation.workspace.id`, `documentation.templates.prd_feature`.
- `.snap/manifests/_taxonomy.json` (cache of domain + journey page IDs).

## Tasks

### A. Skip if platform = none

```bash
PLATFORM=$(jq -r '.documentation.platform // "none"' <<<"$CONFIG_JSON")
```

- `$PLATFORM == "none"` → log notice, `progress.sh step --status=skip`, stop.
- `$PLATFORM ∉ {affine, notion}` → abort with error pointing to `/snap:init`.

### B. Read paths

```bash
FUNCTIONAL_ROOT=$(jq -r '.documentation.paths.functional_root' <<<"$CONFIG_JSON")
PRD_ROOT=$(jq -r '.documentation.paths.prd_root' <<<"$CONFIG_JSON")
WORKSPACE_ID=$(jq -r '.documentation.workspace.id // ""' <<<"$CONFIG_JSON")
PRD_TEMPLATE_ID=$(jq -r '.documentation.templates.prd_feature // ""' <<<"$CONFIG_JSON")
```

Both roots are guaranteed non-empty when `$PLATFORM != "none"` (load-config
injects defaults).

`PRD_TEMPLATE_ID` is **optional**. When the user sets
`documentation.templates.prd_feature` (a remote page ID in their workspace),
the PRD page is cloned from that template. When it is null/absent,
`PRD_TEMPLATE_ID` resolves to the empty string and the page is created blank
(default behavior — absence never breaks publishing).

The PRD feature page title follows a **fixed convention** (`story_name`); it is
not configurable.

### C. Per feature — dispatch to snap-publisher

For each manifest in `.snap/manifests/*.manifest.json` (skip `_taxonomy.json`) :

1. **Prepare brief** (shell-pure, skip-check inside) :
   ```bash
   BRIEF=$(bash skills/_shared/publish-prd.sh prepare \
     --project-root="$PWD" --manifest="$MANIFEST")
   fid=$(echo "$BRIEF" | jq -r '.fid')
   skip=$(echo "$BRIEF" | jq -r '.skip')
   ```

2. **Skip already-synced features** (idempotent re-run) :
   ```bash
   if [ "$skip" = "true" ]; then
     reason=$(echo "$BRIEF" | jq -r '.skip_reason')
     echo "skip $fid ($reason)"
     bash skills/_shared/progress.sh step --project-root="$PWD" --skill=define \
       --story-id="$fid" --step-num=05 --step-name=publish --status=skip
     continue
   fi
   ```

3. **Build agent prompt** :
   ```bash
   PROMPT=$(bash skills/_shared/publish-prd.sh build-agent-prompt \
     --brief="$BRIEF" \
     --platform="$PLATFORM" --workspace-id="$WORKSPACE_ID" \
     --functional-root="$FUNCTIONAL_ROOT" --prd-root="$PRD_ROOT" \
     --prd-template-id="$PRD_TEMPLATE_ID" \
     --project-root="$PWD")
   ```

4. **Dispatch to snap-publisher** via the Agent tool with
   `subagent_type=snap-publisher`. The sub-agent runs the full MCP sequence
   (create-page-tree → create PRD → set-page-tags → lookup-or-create
   functional_root + per-domain + per-journey → `sync-push.sh ack` → manifest
   schema validation) and returns a single JSON fence.

5. **Parse the outcome** (last JSON fence) :
   ```bash
   STATUS=$(echo "$AGENT_OUTPUT" | jq -r '.status')
   RETRIES=$(echo "$AGENT_OUTPUT" | jq -r '.retries // 0')
   REASON=$(echo "$AGENT_OUTPUT" | jq -r '.reason // empty')
   ```

   - `status == "ok"` → step-level progress = `ok`. Telemetry log includes
     `retries`.
   - `status == "skip"` → already-synced detected mid-flight ; progress = `skip`.
   - `status == "fail"` → the sub-agent already called `sync-push.sh fail`.
     Set `progress.sh step --status=fail` ; continue to next manifest (the
     orchestrator must not abort the whole loop on one bad feature).

### D. Telemetry

```bash
bash skills/_shared/telemetry.sh log \
  --project-root="$PWD" \
  --skill=define \
  --step-num=05 \
  --step-name=publish \
  --status=ok \
  --extra="{\"features\":$N, \"platform\":\"$PLATFORM\", \"retries_total\":$TOTAL_RETRIES}"
```

### E. Progress

```bash
bash skills/_shared/progress.sh step \
  --project-root="$PWD" --skill=define --story-id=_global \
  --step-num=05 --step-name=publish --status=ok

bash skills/_shared/progress.sh finish \
  --project-root="$PWD" --skill=define --story-id=_global --status=ok
```

### F. Cleanup transient state

```bash
bash skills/_shared/define-state.sh wipe --project-root="$PWD"
```

`_taxonomy.json` is **persistent** — keep it.

## Failure handling

- **Sub-agent returns `status=fail`** : the sub-agent owns the manifest
  failure path (`sync-push.sh fail --kind=prd`, sets `refs.prd.sync_status=error`,
  keeps staging). The orchestrator only marks per-step progress and continues.
- **MCP transient errors** : handled inside the sub-agent via
  `retry-policy.sh` with exponential backoff (`SNAP_MCP_RETRY_MAX` default 2,
  `SNAP_MCP_RETRY_BASE_MS` default 500ms). Retries are reported in the agent
  outcome `retries` field for telemetry.
- **MCP non-retryable errors** (`auth-fail`, `not-found`, `malformed-json`,
  `missing/empty <KEY>`, `schema-fail`) : abort the sub-agent for that feature
  (no backoff). Same `sync-push.sh fail` flow ; `/snap:define --resume` retries.
- **Mid-loop partial success** : `/snap:define --resume` re-enters step-05 ;
  features with `refs.prd.sync_status=synced` are skipped by `publish-prd.sh
  prepare` (`brief.skip=true`).

## What this step does NOT do

- ❌ Push a "global PRD" page (v0.1 concept dropped — see `docs/contributing/decisions.md`).
- ❌ Modify domain pages with a "modification log" entry (would bloat).
- ❌ Link journey ↔ PRD (journey is a clean spec ; PRD = external archive).
- ❌ Populate journey body for new journeys (deferred to `/snap:doc-update`).
- ❌ Keep PRD staging file after ack (trashed by `sync-push.sh ack` inside the sub-agent).
- ❌ Invoke MCP directly from this step (subprocesses cannot — see `docs-adapter.sh` header).

## Acceptance check

- Each manifest has `refs.prd.{platform, url, page_id, synced_at,
  sync_status:"synced"}` (or `$PLATFORM == "none"` → step skipped entirely).
- `_taxonomy.json` contains every domain + journey referenced by features.
- `.snap/PRDs/{fid}.md` files all trashed after successful ack.
- `progress.json.in_flight` no longer contains a `define` entry for `_global`
  (purged by `progress.sh finish --status=ok`).

## Next step

_None — terminal step._
