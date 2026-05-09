---
step: 03c-loop-daemon
next_step: 05-finish
description: Generate a daemon.sh script that re-invokes /develop standalone per ticket. No auto-launch.
---

# step-03c — loop daemon

Render `daemon.sh` from a template; the user runs it manually
(`bash daemon.sh -n N`). Each invocation = one Claude session = one ticket.

This step is **terminal for skill side**: after writing daemon.sh, jump straight
to step-05 (no sync — that happens per ticket inside the daemon-spawned
sessions).

## Tasks

### A. Render template

Template at `skills/_shared/templates/develop-daemon.sh.tpl`. Variables:

- `{feature_id}`
- `{queue_path}` — absolute path to `.develop-queue.json`
- `{claude_cmd}` — usually `claude` (read from `$PATH`)
- `{develop_args}` — additional flags carried over (`--dry-run`, etc.)

```bash
bash skills/_shared/render-template.sh \
  --template=skills/_shared/templates/develop-daemon.sh.tpl \
  --vars="$ctx" \
  > .claude/product/features/${feature_id}/daemon.sh
chmod +x .claude/product/features/${feature_id}/daemon.sh
```

### B. Surface usage

Print to stdout:

```
Daemon script generated:
  .claude/product/features/${feature_id}/daemon.sh

Run manually:
  bash .claude/product/features/${feature_id}/daemon.sh -n 5

Each invocation processes one ticket via `claude /develop <ticket-id>`.
The script exits when the queue is empty or after N tickets, whichever first.
```

### C. Telemetry + progress

```bash
bash skills/_shared/telemetry.sh emit \
  --project-root="$PWD" --skill=develop --status=ok \
  --extra='{"loop_mode":"daemon","queue_size":'"$queue_size"'}'

bash skills/_shared/update-progress.sh \
  --project-root="$PWD" --feature-id="$feature_id" \
  --skill=develop --step-num=03c --step-name=loop-daemon --status=ok \
  --note="generated daemon.sh queue=$queue_size"
```

## No auto-launch — why?

Spawning `claude` from inside `claude` would consume nested context, lose the
user's terminal control, and silently double-spend tokens. The user is in the
loop on purpose. Daemon mode is just a script generator.

## Acceptance check

- `daemon.sh` exists and is executable.
- File contains `claude /develop` invocations for the current queue.
- `.develop-queue.json` still on disk (daemon updates it per-run).

## Next step

→ `step-05-finish.md` (skipping step-04 — sync happens per-ticket inside the
daemon's spawned sessions).
