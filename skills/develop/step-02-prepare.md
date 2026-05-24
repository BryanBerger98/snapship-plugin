---
step: 02-prepare
next_step: 03a-standalone
description: Resolve worktree per story_type (dedicated or reuse), checkout/create branch, capture conventions + impact radius.
---

# step-02 — prepare

Set the workspace up before any code is written. v1.2 worktree strategy is
gated by `story_type` (decision #11) and resolved by `worktree-helper.sh`.

## Tasks

### `branch_mode` gate

`branch_mode` (default `true`, resolved in step-00 from `defaults.branch_mode`)
controls whether `/develop` creates/checks-out a dedicated branch. When
`false`, **skip sections A and B entirely** — do not call `worktree-helper.sh`,
do not run `git checkout`/`git checkout -b`. Work on the **current** branch and
set:

```bash
if [ "$branch_mode" = "false" ]; then
  strategy="current-branch"
  branch=$(git rev-parse --abbrev-ref HEAD)
  wt_path="$PWD"
  echo "WARN: branch_mode=false — developing on current branch '$branch' (no branch created)."
  # Still refuse a protected branch (commits land here):
  echo "$CONFIG_JSON" | jq -e --arg b "$branch" \
    '(.repository.protected_branches // []) | index($b) | not' >/dev/null \
    || { echo "ERROR: current branch $branch is protected; checkout a feature branch first"; exit 1; }
fi
```

Then jump straight to section C (cache the resolved values). Sections A and B
below run **only when `branch_mode=true`** (the default).

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

Resolve the configured base branch — new branches fork from it instead of
whatever happens to be checked out. Falls back to `main` when
`repository.default_branch` is absent.

```bash
base_branch=$(jq -r '.repository.default_branch // "main"' <<<"$CONFIG_JSON")

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
    # New worktree or new branch on shared tree, forked from the configured base.
    if git rev-parse --verify "$branch" >/dev/null 2>&1; then
      git checkout "$branch"
    elif git rev-parse --verify "$base_branch" >/dev/null 2>&1; then
      git checkout -b "$branch" "$base_branch"
    else
      echo "WARN: base branch $base_branch not found locally — forking from current HEAD" >&2
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

`base_branch` is resolved in section B when `branch_mode=true`. When
`branch_mode=false` (sections A/B skipped) resolve it here so the value is
always cached for step-04 :

```bash
base_branch="${base_branch:-$(jq -r '.repository.default_branch // "main"' <<<"$CONFIG_JSON")}"

jq -nc --arg s "$strategy" --arg b "$branch" --arg p "$wt_path" --arg base "$base_branch" \
  '{strategy:$s, branch:$b, worktree_path:$p, base_branch:$base}' \
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
format_cmd=$(jq -r '.testing.format_command // empty' <<<"$CONFIG_JSON")
test_cmd=$(jq -r '.testing.test_command // empty' <<<"$CONFIG_JSON")
lint_cmd=$(jq -r '.testing.lint_command // empty' <<<"$CONFIG_JSON")
type_cmd=$(jq -r '.testing.typecheck_command // empty' <<<"$CONFIG_JSON")
```

Each command is optional: when its key is absent or empty, `// empty` yields an
empty string and the command is **skipped silently** (no default is invented,
no error). If absent, fall through to `detect-test-commands.sh` and persist into
config.

### G. Append progress

```bash
bash skills/_shared/progress.sh step \
  --project-root="$PWD" \
  --save-mode="$save_mode" \
  --skill=develop \
  --story-id="$TICKET_ID" \
  --step-num=02 \
  --step-name=prepare \
  --status=ok
```

## Acceptance check

- `git rev-parse --abbrev-ref HEAD` matches `$branch` (when `branch_mode=true`;
  when `false`, stays on the pre-run branch and no branch was created).
- `worktree.json` cached with `{strategy, branch, worktree_path}`.
- Conventions captured (or empty — fine).
- Format / lint / typecheck / test commands resolved (any may be empty — fine).

## Next step

→ `step-03a-standalone.md`
