---
step: 05-push
next_step: 06-index
description: Push each rendered story to the platform via tickets-adapter (CLI > MCP fallback).
---

# step-05 — push

Create one platform ticket per story. Idempotent — re-runs skip stories that
already have a `url` (alias `platform_url`) recorded.

## Tasks

### A. Skip if dry-run

If `--dry-run`, set `SNAP_DRY_RUN=true` for the whole loop. The adapter logs to
telemetry and returns mock IDs; mark progress `skip` with note `dry-run` and
fall through to step-06 (it'll write the draft to `tickets.json` for visibility,
sans remote refs).

### B. Per-story create loop

For each story in dependency-sorted order :

1. **Skip if already pushed** : check
   `.snap/tickets/${feature_id}.draft.json[].url` — non-null means a prior
   run created it; keep the cached `platform_id` / `url` and continue.

2. **Call the adapter** :
   ```bash
   adapter_out=$(bash skills/_shared/tickets-adapter.sh \
     --action=create \
     --project-root="$PWD" \
     --platform="$platform" \
     --title="$story_title" \
     --body="$story_body_rendered" \
     --labels="$story_labels_csv" \
     ${dry_run:+--dry-run})
   rc=$?
   ```

3. **Branch on exit code** :
   - `0` → CLI/dry-run succeeded; parse `result.id`, `result.url` from JSON.
   - `10` → MCP descriptor emitted (JIRA / Linear) : parse `descriptor.tool` +
     `descriptor.args`, invoke the MCP tool, capture `id` + `url` from the
     response.
   - other → push failed; record the error verbatim, stop the loop, mark
     progress `fail` with the failing `local_id`. Re-run via
     `/snap:ticket --resume` skips the already-pushed stories.

4. **Cache result** in `.snap/tickets/${feature_id}.draft.json` :
   ```json
   {
     "local_id": "t-001",
     "platform_id": "42",
     "url": "https://github.com/org/repo/issues/42",
     "pushed_at": "2026-05-09T12:34:56Z"
   }
   ```

5. **Rate limiting** : if the platform returns a 429 / "too many requests",
   sleep the `Retry-After` (or 60s) and retry once. Second 429 → fail the loop.

### C. Telemetry

```bash
bash skills/_shared/telemetry.sh log \
  --project-root="$PWD" \
  --skill=ticket \
  --step-num=05 \
  --step-name=push \
  --status=ok \
  --extra='{"platform":"'"$platform"'","tickets_count":'"$count"'}'
```

### D. Progress

```bash
bash skills/_shared/progress.sh step \
  --project-root="$PWD" \
  --skill=ticket \
  --feature-id="$feature_id" \
  --step-num=05 \
  --step-name=push \
  --status=ok
```

## Failure handling

- **Auth error** (401/403) : adapter exits non-zero; surface the platform
  message and abort. Do not retry — re-auth is a user task.
- **Validation error** (e.g. JIRA missing required custom field) : record the
  field name, mark progress `fail`, stop. User edits config and re-runs
  `--resume`.
- **Mid-loop failure** : stories pushed before the failure stay cached in the
  draft; resume picks up the unpushed ones.

## Acceptance check

- Every story has `url` (or all stories have a `dry_run: true` marker).
- `progress.json.in_flight` shows step `05 push` with status `ok` or `skip`.

## Next step

→ `step-06-index.md`
