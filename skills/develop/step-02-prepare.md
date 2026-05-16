---
step: 02-prepare
next_step: 03a-standalone
description: Idempotent branch, conventions load, impact_radius warm-up. Common to standalone + loops.
---

# step-02 — prepare

Set the workspace up before any code is written.

## Tasks

### A. Branch (idempotent)

Branch name from `naming.branch_pattern` applied to the *first* ticket in the
queue (loop) or the single ticket (standalone):

```bash
branch=$(bash skills/_shared/apply-naming.sh \
  --pattern="$(jq -r '.naming.branch_pattern // "feature/{story_id}-{slug}"' <<<"$CONFIG_JSON")" \
  --story-id="$story_id" \
  --slug="$slug")

if git rev-parse --verify "$branch" >/dev/null 2>&1; then
  git checkout "$branch"
else
  git checkout -b "$branch"
fi
```

Refuse to proceed if the resolved branch is in `repository.protected_branches`.

### B. Conventions

Cache `CLAUDE.md`, `CONTRIBUTING.md`, `.cursorrules` content (whichever exist) —
will be passed to the snap-developer agent in step-03a.

```bash
conventions=""
for f in CLAUDE.md CONTRIBUTING.md .cursorrules; do
  [ -f "$f" ] && conventions="${conventions}$(cat "$f")\n\n---\n\n"
done
```

### C. Impact radius (graph-aware)

If `code-review-graph` MCP is reachable, prefetch impact radius for files the
ticket targets — this seeds the analyze step in Phase 1:

```bash
files=$(jq -r '.files[]?' <<< "$ticket_json")
# emit MCP descriptor (exit 10) for get_impact_radius_tool
bash skills/_shared/check-mcp-required.sh --skill=develop --project-root="$PWD" \
  --mcp=code-review-graph || true   # graph optional, not fatal
```

Cache result under `.snap/queues/${story_id}.impact-${local_id}.json` — read
by step-03a Phase 1.

### D. Test commands

```bash
test_cmd=$(jq -r '.testing.test_command // empty' <<<"$CONFIG_JSON")
lint_cmd=$(jq -r '.testing.lint_command // empty' <<<"$CONFIG_JSON")
type_cmd=$(jq -r '.testing.typecheck_command // empty' <<<"$CONFIG_JSON")
```

If absent, fall through to `detect-test-commands.sh` and persist in config.

### E. Append progress

```bash
bash skills/_shared/progress.sh step \
  --project-root="$PWD" \
  --skill=develop \
  --story-id="$story_id" \
  --step-num=02 \
  --step-name=prepare \
  --status=ok
```

## Branch routing

After step-02:

- `target_kind=ticket` → step-03a.
- `target_kind=feature` → step-03b (session loop — delegates to step-03a per
  ticket).

## Acceptance check

- `git rev-parse --abbrev-ref HEAD` matches `$branch`.
- Conventions captured (or empty if no convention files exist — fine).
- Test/lint/typecheck commands resolved.

## Next step

→ `step-03a-standalone.md` (or `03b` per branch routing).
