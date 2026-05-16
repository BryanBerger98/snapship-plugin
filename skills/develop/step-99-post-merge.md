---
step: 99-post-merge
description: Auto-close parent Epic when all its children are done (capability-gated, opt-out via --no-epic-close).
---

# step-99 — post-merge

Triggered **after** the PR for a ticket has been merged. Out-of-band : not
chained from step-05 (that step runs at PR creation, not at merge time).

Invoke explicitly when a merge happens :

```
/develop --post-merge --ticket=<platform_id> [--no-epic-close]
```

CI or a merge-webhook can also call this entry point.

## Tasks

### A. Fetch the merged ticket

```bash
ticket_resp=$(bash skills/_shared/tickets-adapter.sh \
  --action=get --platform="$PLATFORM" --ticket-id="$TICKET_ID" \
  --project-root="$PWD")
ok=$(jq -r '.ok // false' <<<"$ticket_resp")
[ "$ok" = "true" ] || {
  echo "ERROR: cannot fetch ticket $TICKET_ID" >&2
  exit 1
}
ticket_json=$(jq -c '.result' <<<"$ticket_resp")
```

### B. Bail-out conditions

```bash
parent_epic_id=$(jq -r '.parent_epic_id // ""' <<<"$ticket_json")
[ -z "$parent_epic_id" ] && {
  echo "post-merge: ticket has no parent Epic — nothing to close."
  exit 0
}

[ "${NO_EPIC_CLOSE:-false}" = "true" ] && {
  echo "post-merge: --no-epic-close set — skipping Epic auto-close."
  exit 0
}
```

### C. Capability gate

```bash
caps=$(bash skills/_shared/tickets-adapter.sh \
  --action=capabilities --platform="$PLATFORM" --project-root="$PWD" \
  | jq -c '.result')
supported=$(jq -r '.supports_epic_auto_close // false' <<<"$caps")

if [ "$supported" != "true" ]; then
  echo "post-merge: $PLATFORM does not support Epic auto-close — skipping."
  exit 0
fi
```

Capability matrix (current static defaults, see `tickets-adapter.sh::capabilities_for`) :

| Platform | `supports_epic_auto_close` | How |
|----------|---------------------------:|-----|
| github   | `false`                    | Sub-issues feature surface-only (no API close). Skip silently. |
| gitlab   | `true`                     | Epic close API. |
| jira     | `true`                     | Transition workflow → `Done`. |
| linear   | `true`                     | State → `Completed`. |

### D. Close the Epic if all children done

```bash
resp=$(bash skills/_shared/tickets-adapter.sh \
  --action=close-epic --platform="$PLATFORM" --ticket-id="$parent_epic_id" \
  --project-root="$PWD")
ok=$(jq -r '.ok // false' <<<"$resp")

if [ "$ok" = "true" ]; then
  closed=$(jq -r '.result.closed // false' <<<"$resp")
  remaining=$(jq -r '.result.children_remaining // 0' <<<"$resp")
  if [ "$closed" = "true" ]; then
    echo "post-merge: Epic $parent_epic_id closed (all children done)."
  else
    echo "post-merge: Epic $parent_epic_id kept open — $remaining child(ren) still in flight."
  fi
else
  err=$(jq -r '.error // "unknown"' <<<"$resp")
  echo "WARN: close-epic call failed — $err (best-effort, not fatal)" >&2
fi
```

Adapter contract for `close-epic` (decision implementation, all gated platforms) :

- Verify every child of `parent_epic_id` has remote status `done`/`closed`.
- If yes : close the Epic (platform-specific API), return
  `{closed:true, children_remaining:0}`.
- If no : leave the Epic open, return `{closed:false, children_remaining:N}`.
- GitHub (unsupported) : posts a single marker comment
  `:white_check_mark: All sub-issues done — Epic ready to close` when `--mark-only`
  is passed ; otherwise returns `supports_epic_auto_close:false` and step-99
  short-circuits via the capability gate above.

### E. Telemetry

```bash
bash skills/_shared/telemetry.sh log \
  --project-root="$PWD" --skill=develop \
  --step-num=99 --step-name=post-merge --status=ok \
  --extra='{"ticket":"'"$TICKET_ID"'","parent_epic":"'"$parent_epic_id"'","closed":'"$closed"'}'
```

## Idempotence

Re-running step-99 over an already-closed Epic is a no-op : adapter checks
remote state first ; `closed:true` on the second call means already in
terminal state.

## Acceptance check

- Action took :
  - skipped (no parent Epic / opt-out / capability missing), **or**
  - Epic closed, **or**
  - Epic kept open with `children_remaining > 0`, **or**
  - best-effort warn logged.
- Never blocks the run.

## Next step

_None — terminal._
