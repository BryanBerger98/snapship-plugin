---
step: 02-prepare
next_step: 03a-standalone
description: Resolve worktree per story_type (dedicated or reuse), checkout/create branch, capture conventions + impact radius.
---

# step-02 — prepare

Set the workspace up before any code is written. v1.2 worktree strategy is
gated by `story_type` (decision #11) and resolved by `worktree-helper.sh`.

## Tasks

### A. Worktree resolve

```bash
ticket_json=$(bash skills/_shared/cache-runtime.sh read "$SUBJECT_ID" ticket.json \
              --project-root="$PWD")
parent_json=$(bash skills/_shared/cache-runtime.sh read "$SUBJECT_ID" parent.json \
              --project-root="$PWD" 2>/dev/null || echo '')

resolve_args=(--ticket-json="$ticket_json" --project-root="$PWD")
[ -n "$parent_json" ] && resolve_args+=(--parent-json="$parent_json")

wt_resp=$(bash skills/_shared/worktree-helper.sh resolve "${resolve_args[@]}")
strategy=$(jq -r '.strategy'      <<<"$wt_resp")  # dedicated | reuse
branch=$(jq -r   '.branch_name'   <<<"$wt_resp")
wt_path=$(jq -r  '.worktree_path' <<<"$wt_resp")
```

Failure modes :

- `story_type=epic` → helper exits 1 (this is step-01's job to filter ; defensive).
- `branch_name` missing on ticket → helper exits 1. Run `/snap:ticket` step-04
  (apply-naming) first.

Refuse to proceed if `branch` is in `repository.protected_branches` :

```bash
echo "$CONFIG_JSON" | jq -e --arg b "$branch" \
  '(.repository.protected_branches // []) | index($b) | not' >/dev/null \
  || { echo "ERROR: branch $branch is protected"; exit 1; }
```

### B. Branch checkout (strategy-aware)

```bash
case "$strategy" in
  reuse)
    # Task child of US — reuse parent worktree. Branch must already exist.
    if ! git rev-parse --verify "$branch" >/dev/null 2>&1; then
      echo "ERROR: reuse strategy but branch $branch does not exist locally." >&2
      echo "Has the parent User Story been developed yet?" >&2
      exit 1
    fi
    echo "WARN: reusing parent User Story worktree on branch $branch"
    git checkout "$branch"
    ;;

  dedicated)
    # New worktree or new branch on shared tree.
    if git rev-parse --verify "$branch" >/dev/null 2>&1; then
      git checkout "$branch"
    else
      git checkout -b "$branch"
    fi
    ;;

  *)
    echo "ERROR: unknown worktree strategy: $strategy" >&2
    exit 1
    ;;
esac
```

### C. Track worktree path in cache

```bash
jq -nc --arg s "$strategy" --arg b "$branch" --arg p "$wt_path" \
  '{strategy:$s, branch:$b, worktree_path:$p}' \
  | bash skills/_shared/cache-runtime.sh write "$SUBJECT_ID" worktree.json \
      --project-root="$PWD"
```

### D. Conventions

Cache `CLAUDE.md`, `CONTRIBUTING.md`, `.cursorrules` content (whichever exist).
The developer agent will read them.

```bash
conventions=""
for f in CLAUDE.md CONTRIBUTING.md .cursorrules; do
  [ -f "$f" ] && conventions="${conventions}$(cat "$f")\n\n---\n\n"
done
printf '%s' "$conventions" \
  | bash skills/_shared/cache-runtime.sh write "$SUBJECT_ID" conventions.md \
      --project-root="$PWD"
```

### E. Impact radius (graph-aware, optional)

When `code-review-graph` MCP is reachable, prefetch impact radius for files the
ticket targets :

```bash
files_json=$(jq -c '.files // []' <<<"$ticket_json")
if [ "$(jq 'length' <<<"$files_json")" -gt 0 ]; then
  # MCP descriptor (exit 10) signals the orchestrator to invoke the tool.
  bash skills/_shared/check-mcp-required.sh --skill=develop --project-root="$PWD" \
    --mcp=code-review-graph || true   # graph optional, not fatal
  # Orchestrator persists impact.json into the ephemeral subject.
fi
```

### F. Test commands

```bash
test_cmd=$(jq -r '.testing.test_command // empty' <<<"$CONFIG_JSON")
lint_cmd=$(jq -r '.testing.lint_command // empty' <<<"$CONFIG_JSON")
type_cmd=$(jq -r '.testing.typecheck_command // empty' <<<"$CONFIG_JSON")
```

If absent, fall through to `detect-test-commands.sh` and persist into config.

### G. Append progress

```bash
bash skills/_shared/progress.sh step \
  --project-root="$PWD" \
  --skill=develop \
  --story-id="$TICKET_ID" \
  --step-num=02 \
  --step-name=prepare \
  --status=ok
```

## Acceptance check

- `git rev-parse --abbrev-ref HEAD` matches `$branch`.
- `worktree.json` cached with `{strategy, branch, worktree_path}`.
- Conventions captured (or empty — fine).
- Test / lint / typecheck commands resolved.

## Next step

→ `step-03a-standalone.md`
