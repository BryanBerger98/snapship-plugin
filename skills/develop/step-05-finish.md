---
step: 05-finish
description: Close the run — meta.json state advance, summary, propose `/qa`. Terminal step.
---

# step-05 — finish

Wrap up: persist run state, emit summary, hand off to `/qa`.

This step has no `next_step` — it is terminal.

## Tasks

### A. Advance feature state

```bash
processed=$(jq '.processed | length' .develop-queue.json 2>/dev/null || echo 0)
total=$(jq '.tickets | length' "$tickets_file")
all_done=$( [ "$processed" -eq "$total" ] && echo true || echo false )

new_state="in_progress"
[ "$all_done" = "true" ] && new_state="developed"

jq --arg s "$new_state" '.state = $s | .updated_at = (now | todate)' \
  ".claude/product/features/${feature_id}/meta.json" \
  > /tmp/meta.tmp && mv /tmp/meta.tmp \
  ".claude/product/features/${feature_id}/meta.json"
```

### B. Cleanup

```bash
trash .claude/product/features/${feature_id}/.develop-queue.json 2>/dev/null || true
trash .claude/product/features/${feature_id}/.develop-impact-*.json 2>/dev/null || true
trash .claude/product/features/${feature_id}/.develop-sync-*.json 2>/dev/null || true
```

### C. Update feature index

```bash
bash skills/_shared/update-index.sh --project-root="$PWD"
```

Refreshes `.claude/product/index.md` with the new state + commit count.

### D. Telemetry + progress

```bash
bash skills/_shared/telemetry.sh emit \
  --project-root="$PWD" --skill=develop --status=ok \
  --extra='{"feature_state":"'"$new_state"'","tickets_processed":'"$processed"'}'

bash skills/_shared/update-progress.sh \
  --project-root="$PWD" --feature-id="$feature_id" \
  --skill=develop --step-num=05 --step-name=finish --status=ok \
  --note="state=$new_state"
```

### E. Surface summary + hand-off

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
Re-run: `/develop --resume` (session) or re-launch `daemon.sh` (daemon).
```

## Idempotence

Re-running step-05 over an already-finished run rewrites the same fields
(meta.json state already `developed`, queue file already absent — `trash` is
no-op). Safe under `/develop --resume`.

## Acceptance check

- `meta.json` `state` advanced (`developed` or remains `in_progress`).
- Queue + transient files cleaned.
- `progress.md` ends with `develop step-05 finish — ok`.

## Next step

_None — terminal step. User invokes `/qa` next._
