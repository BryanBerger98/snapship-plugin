---
step: 05-finish
description: Close the run — manifest state advance, summary, propose `/qa`. Terminal step.
---

# step-05 — finish

Wrap up: persist run state, emit summary, hand off to `/qa`.

This step has no `next_step` — it is terminal.

## Tasks

### A. Advance feature state

```bash
tickets_file=".snap/tickets/${feature_id}.json"
queue_file=".snap/queues/${feature_id}.develop.json"
processed=$(jq '.processed | length' "$queue_file" 2>/dev/null || echo 0)
total=$(jq '.tickets | length' "$tickets_file")
all_done=$( [ "$processed" -eq "$total" ] && echo true || echo false )

manifest=".snap/manifests/${feature_id}.manifest.json"
current_state=$(jq -r '.state' "$manifest")
new_state="$current_state"
[ "$all_done" = "true" ] && new_state="developed"

NOW=$(date -u +%FT%TZ)
tmp=$(mktemp)
jq --arg s "$new_state" --arg ts "$NOW" \
  '.state = $s | .updated_at = $ts' \
  "$manifest" > "$tmp" && mv "$tmp" "$manifest"
```

### B. Cleanup

```bash
trash "$queue_file" 2>/dev/null || true
trash .snap/queues/${feature_id}.impact-*.json 2>/dev/null || true
trash .snap/queues/${feature_id}.sync.json 2>/dev/null || true
trash .snap/queues/${feature_id}.pr-context.json 2>/dev/null || true
trash .snap/queues/${feature_id}.review-context.json 2>/dev/null || true
```

### C. Telemetry + progress

```bash
bash skills/_shared/telemetry.sh log \
  --project-root="$PWD" --skill=develop \
  --step-num=05 --step-name=finish --status=ok \
  --extra='{"feature_state":"'"$new_state"'","tickets_processed":'"$processed"'}'

bash skills/_shared/progress.sh step \
  --project-root="$PWD" \
  --skill=develop \
  --feature-id="$feature_id" \
  --step-num=05 \
  --step-name=finish \
  --status=ok

bash skills/_shared/progress.sh finish \
  --project-root="$PWD" \
  --skill=develop \
  --feature-id="$feature_id" \
  --status=ok
```

### D. Surface summary + hand-off

Print to stdout:

```
/develop done — feature ${feature_id}:
  - Tickets processed: $processed / $total
  - Branch: $branch
  - PR: $pr_url

Next: run `/qa` to validate against AC + wireframes + regression.
```

If `all_done = false` (loop interrupted, `next-ticket` skips):

```
Some tickets remain (todo: t-007, blocked: t-009).
Re-run: `/develop --resume`.
```

## Idempotence

Re-running step-05 over an already-finished run rewrites the same fields
(manifest state already `developed`, queue file already absent — `trash` is
no-op). Safe under `/develop --resume`.

## Acceptance check

- Manifest `state` advanced (`developed` or remains at current).
- Queue + transient files cleaned.
- `progress.json.in_flight` no longer contains a `develop` entry for the
  feature.

## Next step

_None — terminal step. User invokes `/qa` next._
