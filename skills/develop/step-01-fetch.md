---
step: 01-fetch
next_step: 02-prepare
description: Hydrate target ticket(s). Cache-first; fall back to platform fetch via tickets-adapter.
---

# step-01 — fetch

Load the ticket(s) the run will work on. Cache-first to avoid platform calls.

## Tasks

### A. Standalone mode (target_kind=ticket)

1. Resolve via cache:
   ```bash
   ticket_json=$(jq --arg id "$ticket_id" \
     '.tickets[] | select(.platform_id == $id or .local_id == $id)' \
     ".claude/product/features/${feature_id}/tickets.json")
   ```
2. Cache miss → platform fetch:
   ```bash
   bash skills/_shared/tickets-adapter.sh \
     --action=get --platform="$platform" --id="$ticket_id" \
     --project-root="$PWD"
   # exits 10 (MCP descriptor) → invoke MCP → merge into tickets.json
   ```
3. Validate the ticket has minimal fields (`title`, `acceptance_criteria` non-empty
   or explicit `tech_notes`). If neither → AskUserQuestion: "Proceed without AC?
   (skip / cancel)".

### B. Loop mode (target_kind=feature)

1. Read all tickets where `status in (todo, in_progress)` from tickets.json.
2. Order by `priority` (P0→P3), then `local_id` ascending.
3. Optionally filter by `--label=` if user passed it.
4. Stash queue in `.claude/product/features/${feature_id}/.develop-queue.json`:
   ```json
   {
     "queue": ["t-001", "t-002", "t-003"],
     "processed": [],
     "started_at": "<ISO-8601>",
     "loop_mode": "session"
   }
   ```

### C. Sync ticket status (idempotent)

Mark tickets we plan to touch as `in_progress` locally + remote (best-effort):

```bash
jq --arg lid "$lid" \
  '(.tickets[] | select(.local_id == $lid)).status = "in_progress"' \
  ".claude/product/features/${feature_id}/tickets.json" \
  > .tmp && mv .tmp ".claude/product/features/${feature_id}/tickets.json"

bash skills/_shared/tickets-adapter.sh \
  --action=update --platform="$platform" --id="$platform_id" \
  --status="in_progress" --project-root="$PWD" || true
```

Remote update failures are non-fatal — local cache still drives behaviour.

## Append progress

```bash
bash skills/_shared/update-progress.sh \
  --project-root="$PWD" --feature-id="$feature_id" \
  --skill=develop --step-num=01 --step-name=fetch --status=ok \
  --note="$( [ "$target_kind" = "ticket" ] && echo "$ticket_id" || echo "queue=$count" )"
```

## Acceptance check

- Standalone: `ticket_json` materialised.
- Loop: `.develop-queue.json` written with non-empty `queue[]`.

## Next step

→ `step-02-prepare.md`
