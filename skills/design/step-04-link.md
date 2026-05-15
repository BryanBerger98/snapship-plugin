---
step: 04-link
description: Update each UI ticket with design_screen + design_url + design_mode; re-validate tickets.json. Terminal step.
---

# step-04 — link

Final step. Back-link the design gallery into every UI ticket so `/develop`,
`/qa`, and human reviewers can jump straight to the hi-fi reference.

Terminal — no `next_step`.

## Tasks

### A. Build screen → URL map

```bash
gallery_url=$(jq -r '.refs.design_gallery.url // ""' \
  ".snap/manifests/${feature_id}.manifest.json")
```

Each screen anchors via markdown heading slug (`#signup-screen`):

```json
{
  "signup-screen": "https://docs/.../design#signup-screen",
  "dashboard":     "https://docs/.../design#dashboard"
}
```

### B. Per-ticket update

For each `local_id` in `.snap/designs/${feature_id}.draft.json[].ui_tickets`:

1. Look up screen via `screen_hint`.
2. Determine `design_mode` for the ticket:
   - `"mockup"` — new hi-fi asset produced in step-03.
   - `"reused"` — step-02 decided to reuse the wireframe artifact verbatim
     (no new asset).
3. Patch the entry in `.snap/tickets/${feature_id}.json`:
   ```bash
   tmp=$(mktemp)
   jq --arg lid "$local_id" --arg sid "$screen_id" \
      --arg url "$gallery_url#$screen_id" \
      --arg mode "$design_mode" \
     '(.tickets[] | select(.local_id == $lid))
       |= (.design_screen = $sid
         | .design_url = $url
         | .design_mode = $mode)' \
     ".snap/tickets/${feature_id}.json" > "$tmp" \
     && mv "$tmp" ".snap/tickets/${feature_id}.json"
   ```
4. If the ticket was pushed to a platform (`url` set), re-render body via
   `tickets-adapter.sh --action=update` so the design link surfaces in the
   remote ticket. The resolved ticket template consumes `design_url` +
   `design_screen` + `design_mode`.

### C. Validate tickets.json

```bash
ajv validate -s skills/_shared/schemas/tickets.schema.json \
  -d ".snap/tickets/${feature_id}.json" \
  --spec=draft2020 --strict=false
```

Failure → restore pre-mutation tickets.json and mark progress `fail`.

### D. State transition

Update manifest `state` → `designed`:

```bash
NOW=$(date -u +%FT%TZ)
tmp=$(mktemp)
jq --arg ts "$NOW" '.state = "designed" | .updated_at = $ts' \
  ".snap/manifests/${feature_id}.manifest.json" > "$tmp" \
  && mv "$tmp" ".snap/manifests/${feature_id}.manifest.json"
```

### E. Cleanup + telemetry + progress

```bash
trash ".snap/designs/${feature_id}.draft.json"

bash skills/_shared/telemetry.sh log \
  --project-root="$PWD" --skill=design \
  --step-num=04 --step-name=link --status=ok \
  --extra='{"linked_tickets":'"$count"'}'

bash skills/_shared/progress.sh step \
  --project-root="$PWD" \
  --skill=design \
  --feature-id="$feature_id" \
  --step-num=04 \
  --step-name=link \
  --status=ok

bash skills/_shared/progress.sh finish \
  --project-root="$PWD" \
  --skill=design \
  --feature-id="$feature_id" \
  --status=ok
```

## Idempotence

Re-running over an already-linked tickets.json is a no-op (jq sets the same
value). Safe under `/design --resume`.

## Acceptance check

- Every UI ticket has `design_screen`, `design_url`, and `design_mode` set.
- `.snap/tickets/${feature_id}.json` validates against schema.
- Manifest `state = "designed"`.
- `progress.json.in_flight` no longer contains a `design` entry for the
  feature.

## Next step

_None — terminal step._
