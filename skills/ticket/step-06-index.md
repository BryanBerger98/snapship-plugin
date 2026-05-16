---
step: 06-index
description: Promote ephemeral drafts → `.snap/tickets/${story_id}.json`, ack manifest, surface summary table, purge ephemeral cache (mandatory). Terminal step.
---

# step-06 — index

Terminal step. Move the now-pushed drafts from the ephemeral cache to the
canonical `.snap/tickets/${story_id}.json`, ack the batch into
`manifest.refs.tickets`, validate, surface a summary table to the user,
**and purge the ephemeral subject** (decision #2 — mandatory, even on
failure).

This step has no `next_step` — it is terminal.

## Inputs

- `.snap/.runtime/<SUBJECT_ID>/drafts.json` — drafts after step-05 carrying
  `platform_id` + `url` (or `status=blocked`).
- `.snap/manifests/${story_id}.manifest.json` — only in normal mode (no
  manifest under `--standalone`).

## Tasks

### A. Promote drafts → `tickets.json`

Standalone (`SNAP_STANDALONE=true`) **skips** this section — there is no
feature manifest, so the canonical persistent index is the tracker itself.
The summary table (section E) is the final user-visible artefact.

Normal mode :

```bash
drafts=$(bash skills/_shared/cache-runtime.sh read \
  "$SUBJECT_ID" drafts.json --project-root="$PWD")
dst=".snap/tickets/${story_id}.json"
NOW=$(date -u +%FT%TZ)

printf '%s' "$drafts" | jq --arg fid "$story_id" \
   --arg plat "$platform" \
   --arg ts "$NOW" '
  {
    story_id: $fid,
    platform: $plat,
    synced_at: $ts,
    tickets: [
      .[] | {
        local_id,
        platform_id,
        url,
        title,
        description,
        story_type,
        commit_type,
        parent_epic_id,
        parent_story_id,
        priority,
        status: (.status // "todo"),
        labels,
        assignees,
        milestone,
        target_version,
        acceptance_criteria,
        tech_notes,
        files,
        edge_cases,
        wireframe_screen,
        wireframe_url,
        depends_on,
        estimated_size,
        branch_name,
        updated_at: $ts
      } | with_entries(select(.value != null))
    ]
  }' > "$dst"
```

### B. Validate against schema

```bash
ajv validate -s skills/_shared/schemas/tickets.schema.json \
  -d "$dst" --spec=draft2020 --strict=false
```

If validation fails, **keep** `tickets.json` for debugging, mark progress
`fail`, surface the ajv error verbatim, **and still purge the ephemeral
subject** (decision #2). Do not ack.

### C. Ack into `manifest.refs.tickets`

Skip under `--standalone` (no manifest).

```bash
ANCHOR_URL=$(jq -r '.tickets[0].url // ""' "$dst")

bash skills/_shared/sync-push.sh ack \
  --project-root="$PWD" \
  --story-id="$story_id" \
  --kind=tickets \
  --platform="$platform" \
  --url="$ANCHOR_URL" \
  --no-trash
```

`sync-push.sh ack` updates
`manifest.refs.tickets = { platform, url, synced_at, sync_status: "synced" }`.
`--no-trash` keeps `tickets.json` in place (it IS the persistent cache,
not staging).

Re-validate manifest :
```bash
ajv validate -s skills/_shared/schemas/manifest.schema.json \
  -d ".snap/manifests/${story_id}.manifest.json" \
  --spec=draft2020 --strict=false
```

### D. State transition

Skip under `--standalone`. Update manifest `state` `defined → ticketed` :

```bash
tmp=$(mktemp)
jq --arg ts "$NOW" '.state = "ticketed" | .updated_at = $ts' \
  ".snap/manifests/${story_id}.manifest.json" > "$tmp" \
  && mv "$tmp" ".snap/manifests/${story_id}.manifest.json"
```

### E. Summary table

Surface a markdown table to the user :

```text
| local_id | story_type   | platform_id | URL                                         | status   |
|----------|--------------|-------------|---------------------------------------------|----------|
| t-001    | epic         | #41         | https://github.com/o/r/issues/41            | done     |
| t-002    | user-story   | #42         | https://github.com/o/r/issues/42            | done     |
| t-003    | task         | —           | —                                           | blocked  |
```

Blocked rows include the parent-failure reason inline below the table.

### F. Mandatory ephemeral purge (decision #2)

```bash
if [ "${KEEP_RUNTIME:-false}" = "true" ]; then
  echo "WARN: --keep-runtime set — ephemeral subject ${SUBJECT_ID} preserved at $(bash skills/_shared/cache-runtime.sh path "$SUBJECT_ID" --project-root="$PWD")" >&2
else
  bash skills/_shared/cache-runtime.sh purge "$SUBJECT_ID" --project-root="$PWD"
fi
```

The `--keep-runtime` flag (parsed in step-00) is a **debug-only** opt-out :
its presence is surfaced in the summary so users can locate the cache for
inspection. The step-00 EXIT trap also calls `purge` as a defence-in-depth
in case this step itself fails — purge is idempotent.

### G. Telemetry + progress

```bash
bash skills/_shared/telemetry.sh log \
  --project-root="$PWD" \
  --skill=ticket \
  --step-num=06 \
  --step-name=index \
  --status=ok \
  --extra='{"tickets_count":'"$count"',"blocked":'"$blocked_count"'}'

bash skills/_shared/progress.sh step \
  --project-root="$PWD" \
  --skill=ticket \
  --story-id="$story_id" \
  --step-num=06 \
  --step-name=index \
  --status=ok

bash skills/_shared/progress.sh finish \
  --project-root="$PWD" \
  --skill=ticket \
  --story-id="$story_id" \
  --status=ok
```

## Acceptance check

- Normal mode :
  - `.snap/tickets/${story_id}.json` exists, validates, has ≥ 1 entry.
  - `manifest.refs.tickets.sync_status = "synced"`.
  - Manifest `state = "ticketed"`.
- Standalone mode :
  - No `tickets.json` written, no manifest touched.
  - Summary table surfaced.
- **Always** :
  - Summary table surfaced to the user (with blocked rows when present).
  - `.snap/.runtime/<SUBJECT_ID>/` no longer exists, unless
    `--keep-runtime` was set.
  - `progress.json.in_flight` no longer contains a `ticket` entry.

## Next step

_None — terminal step._
