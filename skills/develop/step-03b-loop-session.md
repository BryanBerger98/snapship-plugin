---
step: 03b-loop-session
next_step: 04-sync
description: Iterate the queue in the same Claude session — for each ticket, run step-03a, commit, advance.
---

# step-03b — loop session

Same-session loop. Each ticket gets its own Phase 1+2 cycle and atomic commit.
Branch is shared (the feature branch, set in step-02).

## Tasks

```
queue=$(jq -r '.queue[]' .develop-queue.json)

for local_id in $queue; do
  # 1. Hydrate one ticket from cache.
  ticket_json=$(jq --arg id "$local_id" '.tickets[] | select(.local_id == $id)' \
    "$tickets_file")

  # 2. Run step-03a (skill loads its instructions) → returns sha + cycles_used.
  if ! run_step_03a "$ticket_json"; then
    case "$fail_strategy" in
      next-ticket)
        # Mark blocked, advance.
        jq --arg lid "$local_id" \
          '(.tickets[] | select(.local_id == $lid)).status = "blocked"' \
          "$tickets_file" > "$tickets_file.tmp" \
          && mv "$tickets_file.tmp" "$tickets_file"
        ;;
      stop)
        echo "ERROR: ticket $local_id failed under fail_strategy=stop" >&2
        exit 1
        ;;
      retry)
        # step-03a already retried once; check --retry-fallback.
        case "$retry_fallback" in
          next-ticket) ;; # noop, advance
          *) exit 1 ;;
        esac
        ;;
    esac
  fi

  # 3. Update queue state.
  jq --arg lid "$local_id" \
    '.processed += [$lid] | .queue |= map(select(. != $lid))' \
    .develop-queue.json > .develop-queue.json.tmp \
    && mv .develop-queue.json.tmp .develop-queue.json
done
```

## Resume

If interrupted, `/develop --resume`:
1. Reads `.develop-queue.json` — `processed[]` is the catch-up state.
2. Resumes at the first ticket in `queue[]` not in `processed[]`.
3. If the last `processed` ticket has no `commit_sha` in tickets.json, treat it
   as half-done — re-run step-03a for it (Phase 1 + 2 are idempotent under amend).

## Failure handling

- One ticket's Phase 1 fails → governed by `fail_strategy` (above).
- `git commit --amend` conflicts (race condition with another process) → halt
  with `loop_corrupted`; user investigates.

## Append progress

Per-ticket progress entries are appended by step-03a. step-03b adds a final
summary:

```bash
bash skills/_shared/update-progress.sh \
  --project-root="$PWD" --feature-id="$feature_id" \
  --skill=develop --step-num=03b --step-name=loop-session --status=ok \
  --note="processed=$(jq '.processed | length' .develop-queue.json) blocked=$blocked_count"
```

## Acceptance check

- `.develop-queue.json` `queue` is empty (or only contains items skipped under
  `next-ticket`).
- Each processed ticket has a `commit_sha`.

## Next step

→ `step-04-sync.md`
