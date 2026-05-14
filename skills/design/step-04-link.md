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
gallery_url=$(jq -r --arg fid "$feature_id" \
  '.design_gallery[$fid].url' .claude/product/.docs-cache.json)
```

Each screen anchors via markdown heading slug (`#signup-screen`):

```json
{
  "signup-screen": "https://docs/.../design#signup-screen",
  "dashboard":     "https://docs/.../design#dashboard"
}
```

### B. Per-ticket update

For each `local_id` in `.design-draft.json[].ui_tickets`:

1. Look up screen via `screen_hint`.
2. Determine `design_mode` for the ticket:
   - `"mockup"` — new hi-fi asset produced in step-03.
   - `"reused"` — step-02 decided to reuse the wireframe artifact verbatim
     (no new asset).
3. Patch the entry in `tickets.json`:
   ```bash
   jq --arg lid "$local_id" --arg sid "$screen_id" \
      --arg url "$gallery_url#$screen_id" \
      --arg mode "$design_mode" \
     '(.tickets[] | select(.local_id == $lid))
       |= (.design_screen = $sid
         | .design_url = $url
         | .design_mode = $mode)' \
     ".claude/product/features/${feature_id}/tickets.json" \
     > "${feature_id}-tickets.tmp" \
     && mv "${feature_id}-tickets.tmp" ".claude/product/features/${feature_id}/tickets.json"
   ```
4. If the ticket was pushed to a platform (`platform_url` set), re-render
   body via `tickets-adapter.sh --action=update` so the design link surfaces
   in the remote ticket. Template `ticket-${platform}.md` consumes
   `design_url` + `design_screen` + `design_mode`.

### C. Validate tickets.json

```bash
ajv validate -s skills/_shared/schemas/tickets.schema.json \
  -d ".claude/product/features/${feature_id}/tickets.json" \
  --spec=draft2020 --strict=false
```

Failure → restore pre-mutation tickets.json and mark progress `fail`.

### D. Cleanup + telemetry + progress

```bash
trash ".claude/product/features/${feature_id}/.design-draft.json"

bash skills/_shared/telemetry.sh emit \
  --project-root="$PWD" --skill=design --status=ok \
  --extra='{"linked_tickets":'"$count"'}'

bash skills/_shared/update-progress.sh \
  --project-root="$PWD" --feature-id="$feature_id" \
  --step-num=04 --step-name=link --status=ok --skill=design
```

## Idempotence

Re-running over an already-linked tickets.json is a no-op (jq sets the same
value). Safe under `/design --resume`.

## Acceptance check

- Every UI ticket has `design_screen`, `design_url`, and `design_mode` set.
- `tickets.json` validates against schema.
- `progress.md` ends with `design step-04 link — ok`.

## Next step

_None — terminal step._
