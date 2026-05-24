---
step: 00-init
next_step: 01-fetch
description: Parse args, validate --ticket=<platform_id>, init ephemeral subject, pre-fetch ticket + parent live into cache.
---

# step-00 — init

Bootstrap a `/develop` run. **v1.2 contract** : one ticket per call, identified
by its remote `platform_id`. No PRD lookup, no local `feature_id`, no
session-loop.

## Communication language (`defaults.lang`)

Once `CONFIG_JSON` is loaded below (task 3), resolve the configured language and
respond to the user in it for the whole skill run (prompts, questions,
summaries):

```bash
SNAP_LANG=$(jq -r '.defaults.lang // "fr"' <<<"$CONFIG_JSON")
```

**Directive**: communicate with the user in `$SNAP_LANG` (`fr` = français,
`en` = English, …). Presentation directive only — never translate config keys,
file paths, or code identifiers.

## Tasks

### 1. Parse args

```
/develop --ticket=<platform_id> [--dry-run] [--allow-dirty]
         [--no-epic-close] [--keep-runtime]
         [--resume|-r] [--retry-fallback=next-ticket|stop]
```

- `--ticket=<platform_id>` — **mandatory**. Format validated per platform :

  | Platform | Regex |
  |----------|-------|
  | github   | `^#?[0-9]+$`            (e.g. `#42`, `42`) |
  | gitlab   | `^#?[0-9]+$`            (e.g. `#42`, `42`) |
  | jira     | `^[A-Z][A-Z0-9_]+-[0-9]+$` (e.g. `AUTH-12`) |
  | linear   | `^[A-Z][A-Z0-9_]+-[0-9]+$` (e.g. `ENG-42`) |

  Missing or malformed → fail clean :

  ```
  ERROR: /develop requires --ticket=<platform_id> (got: <input>)
  Expected format for <platform>: <regex>
  ```

- `--dry-run` — skip writes (no commit/push, reviewers run on staged diff).
- `--allow-dirty` — tolerate uncommitted changes pre-run.
- `--no-epic-close` — opt-out from post-merge Epic auto-close (see step-99).
- `--keep-runtime` — **debug only** : do not purge the ephemeral subject at
  step-05 ; surface path in summary.
- `--resume` / `-r` — short-circuit via `progress.sh resume`.

### 2. Resume short-circuit

```bash
resume_line=$(bash skills/_shared/progress.sh resume \
  --project-root="$PWD" \
  --skill=develop \
  --story-id="$ticket_id")
```

Same rc=0/1/2 contract as the other skills.

### 3. Require config + load

```bash
[ -f "$PWD/snap.config.json" ] || {
  echo "ERROR: snap.config.json not found. Run /snap:init first." >&2
  exit 1
}
CONFIG_JSON=$(bash skills/_shared/load-config.sh --project-root="$PWD")
PLATFORM=$(jq -r '.tickets.platform // empty' <<<"$CONFIG_JSON")
[ -z "$PLATFORM" ] || [ "$PLATFORM" = "none" ] && {
  echo "ERROR: tickets.platform must be set (got: ${PLATFORM:-empty})" >&2
  exit 1
}
review_cycles_max=$(jq '.develop.review_cycles_max // 3' <<<"$CONFIG_JSON")
fail_strategy=$(jq -r '.develop.fail_strategy // "next-ticket"' <<<"$CONFIG_JSON")
# defaults toggles — resolve once, reuse in later steps.
save_mode=$(jq -r '.defaults.save_mode // true' <<<"$CONFIG_JSON")
branch_mode=$(jq -r '.defaults.branch_mode // true' <<<"$CONFIG_JSON")
```

**`save_mode`** (default `true`) — when `false`, progress persistence is
disabled. Pass `--save-mode="$save_mode"` to **every** `progress.sh`
`start`/`step`/`finish` call in this skill (the helper turns them into no-ops
when `false`). Reads (`resume`/`list`) are unaffected.

**`branch_mode`** (default `true`) — when `false`, step-02 must skip git branch
creation and work on the current branch (see step-02).

### 4. Pre-flight

- `git rev-parse --is-inside-work-tree` — abort if not in a repo.
- Working tree clean (unless `--allow-dirty`) :

  ```bash
  [ -z "$(git status --porcelain)" ] || { echo "ERROR: dirty tree"; exit 1; }
  ```

- Refuse to commit directly on `repository.protected_branches` (branch is
  resolved in step-02 via worktree-helper).
- Reviewer agents present : `agents/snap-developer.md` and
  `agents/snap-code-reviewer-{technical,functional,security}.md`.

### 5. Init ephemeral subject

```bash
SUBJECT_ID=$(bash skills/_shared/cache-runtime.sh id-gen --prefix=develop)
bash skills/_shared/cache-runtime.sh init "$SUBJECT_ID" --project-root="$PWD"
trap 'bash skills/_shared/cache-runtime.sh purge "'"$SUBJECT_ID"'" \
        --project-root="'"$PWD"'" 2>/dev/null || true' EXIT
```

(`--keep-runtime` skips the trap.)

### 6. Pre-fetch live ticket + parent

```bash
ticket_resp=$(bash skills/_shared/tickets-adapter.sh \
  --action=get --platform="$PLATFORM" --ticket-id="$TICKET_ID" \
  --project-root="$PWD")
ok=$(jq -r '.ok // false' <<<"$ticket_resp")
[ "$ok" = "true" ] || {
  err=$(jq -r '.error // "fetch_failed"' <<<"$ticket_resp")
  echo "ERROR: cannot fetch ticket $TICKET_ID on $PLATFORM — $err" >&2
  exit 1
}
ticket_json=$(jq -c '.result' <<<"$ticket_resp")
printf '%s' "$ticket_json" \
  | bash skills/_shared/cache-runtime.sh write "$SUBJECT_ID" ticket.json
```

If the ticket carries `parent_epic_id` **or** `parent_story_id`, fetch the
parent too :

```bash
parent_pid=$(jq -r '.parent_epic_id // .parent_story_id // empty' <<<"$ticket_json")
if [ -n "$parent_pid" ]; then
  parent_resp=$(bash skills/_shared/tickets-adapter.sh \
    --action=get --platform="$PLATFORM" --ticket-id="$parent_pid" \
    --project-root="$PWD")
  [ "$(jq -r '.ok // false' <<<"$parent_resp")" = "true" ] && \
    jq -c '.result' <<<"$parent_resp" \
    | bash skills/_shared/cache-runtime.sh write "$SUBJECT_ID" parent.json
fi
```

Network failure / 404 / retry exhaustion → fail clean (no offline fallback).

### 7. Append progress

```bash
bash skills/_shared/progress.sh step \
  --project-root="$PWD" \
  --save-mode="$save_mode" \
  --skill=develop \
  --story-id="$TICKET_ID" \
  --step-num=00 \
  --step-name=init \
  --status=ok
```

## Acceptance check

- `TICKET_ID` validated against the platform-specific regex.
- Ephemeral subject created ; `ticket.json` present in cache.
- `parent.json` present when ticket has a parent reference.
- `CONFIG_JSON.tickets.platform != "none"` ; reviewer agents present.

## Next step

→ `step-01-fetch.md`
