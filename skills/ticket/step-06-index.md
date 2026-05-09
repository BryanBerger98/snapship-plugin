---
step: 06-index
description: Persist tickets.json, update meta.json (tickets_count + URLs), validate schemas, cleanup. Terminal step.
---

# step-06 — index

Final step. Promote `.tickets-draft.json` to `tickets.json`, update the feature's
`meta.json`, validate against schemas, drop the draft.

This step has no `next_step` — it is terminal.

## Tasks

### A. Promote draft → tickets.json

```bash
src=".claude/product/features/${feature_id}/.tickets-draft.json"
dst=".claude/product/features/${feature_id}/tickets.json"
jq '[.[] | {ticket_id, title, ac_id, ac_text, labels, depends_on,
            platform_id, platform_url, pushed_at, status: "todo"}]' \
  "$src" > "$dst"
```

### B. Validate against schema

```bash
ajv validate -s skills/_shared/schemas/tickets.schema.json \
  -d ".claude/product/features/${feature_id}/tickets.json" \
  --spec=draft2020 --strict=false
```

If validation fails, restore the draft (keep both files) and mark progress `fail`.
Surface the ajv error verbatim.

### C. Update meta.json

```bash
jq --arg n "$count" --arg ts "$(date -u +%FT%TZ)" \
  '.tickets_count = ($n|tonumber) | .updated_at = $ts | .state = "tickets-pushed"' \
  ".claude/product/features/${feature_id}/meta.json" \
  > "${feature_id}-meta.tmp" \
  && mv "${feature_id}-meta.tmp" ".claude/product/features/${feature_id}/meta.json"
```

Re-validate `meta.json`:
```bash
ajv validate -s skills/_shared/schemas/meta.schema.json \
  -d ".claude/product/features/${feature_id}/meta.json" \
  --spec=draft2020 --strict=false
```

### D. Update top-level index

```bash
bash skills/_shared/update-index.sh --project-root="$PWD"
```

### E. Cleanup

```bash
trash ".claude/product/features/${feature_id}/.tickets-draft.json"
```

(Use `trash` per global rule, not `rm`.)

### F. Telemetry + progress

```bash
bash skills/_shared/telemetry.sh emit \
  --project-root="$PWD" \
  --skill=ticket \
  --status=ok \
  --duration-ms="$elapsed_ms" \
  --extra='{"tickets_count":'"$count"'}'

bash skills/_shared/update-progress.sh \
  --project-root="$PWD" \
  --feature-id="$feature_id" \
  --step-num=06 \
  --step-name=index \
  --status=ok \
  --skill=ticket
```

## Acceptance check

- `tickets.json` exists, validates, has ≥ 1 entry.
- `meta.json` `tickets_count` matches the array length.
- `.tickets-draft.json` removed.
- `progress.md` ends with `ticket step-06 index — ok`.

## Next step

_None — terminal step._
