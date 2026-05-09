---
step: 04-link
description: Update each UI ticket with wireframe_screen + wireframe_url; re-validate tickets.json. Terminal step.
---

# step-04 — link

Final step. Back-link the gallery into every UI ticket so `/develop` (and human
reviewers) can jump straight to the wireframe.

This step has no `next_step` — it is terminal.

## Tasks

### A. Build the screen → URL map

```bash
gallery_url=$(jq -r --arg fid "$feature_id" \
  '.wireframes_gallery[$fid].url' .claude/product/.docs-cache.json)
```

Each screen anchors to a section of the gallery via the markdown heading slug
(`#signup-screen`). Build a map:

```json
{
  "signup-screen": "https://affine/.../wireframes#signup-screen",
  "verify-screen": "https://affine/.../wireframes#verify-screen"
}
```

### B. Per-ticket update

For each `local_id` in `.wireframes-draft.json[].ui_tickets`:

1. Look up the matching screen via the `screen_hint` recorded in step-01.
2. Patch the ticket entry in `tickets.json`:
   ```bash
   jq --arg lid "$local_id" --arg sid "$screen_id" --arg url "$gallery_url#$screen_id" \
     '(.tickets[] | select(.local_id == $lid))
       |= (.wireframe_screen = $sid | .wireframe_url = $url)' \
     ".claude/product/features/${feature_id}/tickets.json" \
     > "${feature_id}-tickets.tmp" \
     && mv "${feature_id}-tickets.tmp" ".claude/product/features/${feature_id}/tickets.json"
   ```

3. If the ticket was pushed to a platform (`platform_url` set), also update the
   remote ticket body via `tickets-adapter.sh --action=update --body=...`. The
   model re-renders the body via `templates/ticket-${platform}.md` with the new
   `wireframe_url` field populated.

### C. Validate tickets.json

```bash
ajv validate -s skills/_shared/schemas/tickets.schema.json \
  -d ".claude/product/features/${feature_id}/tickets.json" \
  --spec=draft2020 --strict=false
```

Failure → restore the pre-mutation tickets.json and mark progress `fail`.

### D. Cleanup + telemetry + progress

```bash
trash ".claude/product/features/${feature_id}/.wireframes-draft.json"

bash skills/_shared/telemetry.sh emit \
  --project-root="$PWD" --skill=wireframe --status=ok \
  --extra='{"linked_tickets":'"$count"'}'

bash skills/_shared/update-progress.sh \
  --project-root="$PWD" --feature-id="$feature_id" \
  --step-num=04 --step-name=link --status=ok --skill=wireframe
```

## Idempotence

Re-running step-04 over an already-linked tickets.json is a no-op (the jq
expression sets the same value). Safe under `/wireframe --resume`.

## Acceptance check

- Every UI ticket has both `wireframe_screen` and `wireframe_url` set.
- `tickets.json` validates against schema.
- `progress.md` ends with `wireframe step-04 link — ok`.

## Next step

_None — terminal step._
