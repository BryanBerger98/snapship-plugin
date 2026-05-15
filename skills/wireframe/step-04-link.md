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
gallery_url=$(jq -r '.refs.wireframes_gallery.url // ""' \
  ".snap/manifests/${feature_id}.manifest.json")
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

For each `local_id` in `.snap/wireframes/${feature_id}.draft.json[].ui_tickets`:

1. Look up the matching screen via the `screen_hint` recorded in step-01.
2. Patch the ticket entry in `.snap/tickets/${feature_id}.json`:
   ```bash
   tmp=$(mktemp)
   jq --arg lid "$local_id" --arg sid "$screen_id" --arg url "$gallery_url#$screen_id" \
     '(.tickets[] | select(.local_id == $lid))
       |= (.wireframe_screen = $sid | .wireframe_url = $url)' \
     ".snap/tickets/${feature_id}.json" > "$tmp" \
     && mv "$tmp" ".snap/tickets/${feature_id}.json"
   ```

3. If the ticket was pushed to a platform (`url` set), also update the
   remote ticket body via `tickets-adapter.sh --action=update --body=...`. The
   model re-renders the body via the resolved ticket template with the new
   `wireframe_url` field populated.

### C. Validate tickets.json

```bash
ajv validate -s skills/_shared/schemas/tickets.schema.json \
  -d ".snap/tickets/${feature_id}.json" \
  --spec=draft2020 --strict=false
```

Failure → restore the pre-mutation tickets.json and mark progress `fail`.

### D. State transition

Update manifest `state` → `wireframed`:

```bash
NOW=$(date -u +%FT%TZ)
tmp=$(mktemp)
jq --arg ts "$NOW" '.state = "wireframed" | .updated_at = $ts' \
  ".snap/manifests/${feature_id}.manifest.json" > "$tmp" \
  && mv "$tmp" ".snap/manifests/${feature_id}.manifest.json"
```

### E. Cleanup + telemetry + progress

```bash
trash ".snap/wireframes/${feature_id}.draft.json"

bash skills/_shared/telemetry.sh log \
  --project-root="$PWD" --skill=wireframe \
  --step-num=04 --step-name=link --status=ok \
  --extra='{"linked_tickets":'"$count"'}'

bash skills/_shared/progress.sh step \
  --project-root="$PWD" \
  --skill=wireframe \
  --feature-id="$feature_id" \
  --step-num=04 \
  --step-name=link \
  --status=ok

bash skills/_shared/progress.sh finish \
  --project-root="$PWD" \
  --skill=wireframe \
  --feature-id="$feature_id" \
  --status=ok
```

## Idempotence

Re-running step-04 over an already-linked tickets.json is a no-op (the jq
expression sets the same value). Safe under `/wireframe --resume`.

## Acceptance check

- Every UI ticket has both `wireframe_screen` and `wireframe_url` set.
- `.snap/tickets/${feature_id}.json` validates against schema.
- Manifest `state = "wireframed"`.
- `progress.json.in_flight` no longer contains a `wireframe` entry for the
  feature.

## Next step

_None — terminal step._
