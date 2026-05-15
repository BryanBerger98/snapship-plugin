---
step: 06-index
description: Promote draft → .snap/tickets/{fid}.json, ack manifest.refs.tickets via sync-push, validate schemas, drop draft. Terminal step.
---

# step-06 — index

Final step. Promote the draft to the canonical
`.snap/tickets/${feature_id}.json` (cache pointing at remote tickets), ack the
batch into `manifest.refs.tickets` via `sync-push.sh ack`, validate, drop the
draft.

This step has no `next_step` — it is terminal.

## Tasks

### A. Promote draft → tickets.json

```bash
src=".snap/tickets/${feature_id}.draft.json"
dst=".snap/tickets/${feature_id}.json"
NOW=$(date -u +%FT%TZ)

jq --arg fid "$feature_id" \
   --arg plat "$platform" \
   --arg ts "$NOW" '
  {
    feature_id: $fid,
    platform: $plat,
    synced_at: $ts,
    tickets: [
      .[] | {
        local_id,
        platform_id,
        url,
        title,
        description,
        type,
        priority,
        status: (.status // "todo"),
        labels,
        assignees,
        milestone,
        acceptance_criteria,
        tech_notes,
        files,
        edge_cases,
        wireframe_screen,
        wireframe_url,
        depends_on,
        estimated_size,
        updated_at: $ts
      } | with_entries(select(.value != null))
    ]
  }' "$src" > "$dst"
```

### B. Validate against schema

```bash
ajv validate -s skills/_shared/schemas/tickets.schema.json \
  -d ".snap/tickets/${feature_id}.json" \
  --spec=draft2020 --strict=false
```

If validation fails, restore the draft (keep both files) and mark progress
`fail`. Surface the ajv error verbatim. Do **not** ack.

### C. Ack into manifest.refs.tickets

```bash
# Pick the first ticket URL as the "anchor" reference for the batch — the
# canonical pointer is the tracker query; per-ticket URLs live in tickets.json.
ANCHOR_URL=$(jq -r '.tickets[0].url // ""' "$dst")

bash skills/_shared/sync-push.sh ack \
  --project-root="$PWD" \
  --feature-id="$feature_id" \
  --kind=tickets \
  --platform="$platform" \
  --url="$ANCHOR_URL" \
  --no-trash    # tickets.json stays — it IS the cache (not staging)
```

`sync-push.sh ack` updates `manifest.refs.tickets = { platform, url, synced_at,
sync_status: "synced" }`. The `--no-trash` flag keeps `.snap/tickets/{fid}.json`
in place (it is the persistent reference cache, not transient staging — unlike
`.snap/PRDs/{fid}.md`).

Re-validate manifest :
```bash
ajv validate -s skills/_shared/schemas/manifest.schema.json \
  -d ".snap/manifests/${feature_id}.manifest.json" \
  --spec=draft2020 --strict=false
```

### D. State transition

Update manifest `state` from `defined` → `ticketed` :

```bash
tmp=$(mktemp)
jq --arg ts "$NOW" '.state = "ticketed" | .updated_at = $ts' \
  ".snap/manifests/${feature_id}.manifest.json" > "$tmp" \
  && mv "$tmp" ".snap/manifests/${feature_id}.manifest.json"
```

### E. Cleanup

```bash
trash ".snap/tickets/${feature_id}.draft.json"
```

(Use `trash` per global rule, not `rm`.)

### F. Telemetry + progress

```bash
bash skills/_shared/telemetry.sh log \
  --project-root="$PWD" \
  --skill=ticket \
  --step-num=06 \
  --step-name=index \
  --status=ok \
  --extra='{"tickets_count":'"$count"'}'

bash skills/_shared/progress.sh step \
  --project-root="$PWD" \
  --skill=ticket \
  --feature-id="$feature_id" \
  --step-num=06 \
  --step-name=index \
  --status=ok

bash skills/_shared/progress.sh finish \
  --project-root="$PWD" \
  --skill=ticket \
  --feature-id="$feature_id" \
  --status=ok
```

## Acceptance check

- `.snap/tickets/${feature_id}.json` exists, validates, has ≥ 1 entry.
- `manifest.refs.tickets.sync_status = "synced"`.
- Manifest `state = "ticketed"`.
- `.snap/tickets/${feature_id}.draft.json` removed.
- `progress.json.in_flight` no longer contains a `ticket` entry for the
  feature.

## Next step

_None — terminal step._
