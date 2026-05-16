#!/usr/bin/env bash
# /develop step-02 worktree strategy — exercises worktree-helper.sh resolve
# on the 4 story_type cases v1.2 cares about (decision #11).

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WT="${ROOT}/skills/_shared/worktree-helper.sh"

PASS=0
FAIL=0
ERRORS=()

ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1 — $2"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

DIR=$(mktemp -d -t snap-dev-wt-XXXXXX)
trap 'trash "$DIR" 2>/dev/null || true' EXIT

CONFIG='{"defaults":{"worktree":{"path":"./.worktrees","destroy":"after_merge"}}}'

run_resolve() {
  local ticket="$1" parent="${2:-}"
  local args=(resolve --ticket-json="$ticket" --config-json="$CONFIG" --project-root="$DIR")
  [ -n "$parent" ] && args+=(--parent-json="$parent")
  bash "$WT" "${args[@]}"
}

echo "=== /develop step-02 worktree resolve ==="

# Case A : Epic → refused with exit 1.
EPIC='{"local_id":"t-001","title":"Auth platform","story_type":"epic"}'
out=$(run_resolve "$EPIC" 2>&1) ; rc=$?
[ "$rc" = "1" ] && ok "epic.1 Epic refused (exit 1)" || ko "epic.1" "rc=$rc out=$out"
[[ "$out" == *"epic"* ]] && ok "epic.2 error mentions epic" || ko "epic.2" "$out"

# Case B : User Story → dedicated strategy, branch from ticket.branch_name.
US='{"local_id":"t-002","title":"Email signup","story_type":"user-story","branch_name":"feat/t-002-email-signup"}'
out=$(run_resolve "$US")
[ "$(jq -r '.strategy' <<<"$out")" = "dedicated" ] && ok "us.1 US strategy dedicated" \
  || ko "us.1" "got $(jq -r '.strategy' <<<"$out")"
[ "$(jq -r '.branch_name' <<<"$out")" = "feat/t-002-email-signup" ] \
  && ok "us.2 US branch_name preserved" \
  || ko "us.2" "branch=$(jq -r '.branch_name' <<<"$out")"
[[ "$(jq -r '.worktree_path' <<<"$out")" == *"feat/t-002-email-signup" ]] \
  && ok "us.3 US worktree_path under config.path" \
  || ko "us.3" "$(jq -r '.worktree_path' <<<"$out")"

# Case C : Bug → dedicated.
BUG='{"local_id":"t-003","title":"Crash on login","story_type":"bug","branch_name":"fix/t-003-login-crash"}'
out=$(run_resolve "$BUG")
[ "$(jq -r '.strategy' <<<"$out")" = "dedicated" ] && ok "bug.1 Bug strategy dedicated" \
  || ko "bug.1" "$(jq -r '.strategy' <<<"$out")"

# Case D : Task child of US → REUSE parent US branch (no own branch needed).
PARENT_US='{"local_id":"t-002","title":"Email signup","story_type":"user-story","branch_name":"feat/t-002-email-signup"}'
TASK_CHILD_US='{"local_id":"t-004","title":"Validate email format","story_type":"task","parent_story_id":"t-002"}'
out=$(run_resolve "$TASK_CHILD_US" "$PARENT_US")
[ "$(jq -r '.strategy' <<<"$out")" = "reuse" ] && ok "task.1 Task-child-US strategy reuse" \
  || ko "task.1" "$(jq -r '.strategy' <<<"$out")"
[ "$(jq -r '.branch_name' <<<"$out")" = "feat/t-002-email-signup" ] \
  && ok "task.2 Task-child-US reuses US branch" \
  || ko "task.2" "branch=$(jq -r '.branch_name' <<<"$out")"

# Case E : Task child of Bug → dedicated (only US triggers reuse).
PARENT_BUG='{"local_id":"t-003","title":"Crash","story_type":"bug","branch_name":"fix/t-003-crash"}'
TASK_CHILD_BUG='{"local_id":"t-005","title":"Add log","story_type":"task","parent_story_id":"t-003","branch_name":"chore/t-005-add-log"}'
out=$(run_resolve "$TASK_CHILD_BUG" "$PARENT_BUG")
[ "$(jq -r '.strategy' <<<"$out")" = "dedicated" ] && ok "task.3 Task-child-Bug strategy dedicated" \
  || ko "task.3" "$(jq -r '.strategy' <<<"$out")"
[ "$(jq -r '.branch_name' <<<"$out")" = "chore/t-005-add-log" ] \
  && ok "task.4 Task-child-Bug uses its own branch" \
  || ko "task.4" "branch=$(jq -r '.branch_name' <<<"$out")"

# Case F : Task child of Epic → dedicated.
TASK_CHILD_EPIC='{"local_id":"t-006","title":"DB migration","story_type":"task","parent_epic_id":"t-001","branch_name":"chore/t-006-db-mig"}'
out=$(run_resolve "$TASK_CHILD_EPIC")
[ "$(jq -r '.strategy' <<<"$out")" = "dedicated" ] && ok "task.5 Task-child-Epic strategy dedicated" \
  || ko "task.5" "$(jq -r '.strategy' <<<"$out")"

# Case G : standalone Task → dedicated.
TASK_STANDALONE='{"local_id":"t-007","title":"Bump axios","story_type":"task","branch_name":"chore/t-007-bump-axios"}'
out=$(run_resolve "$TASK_STANDALONE")
[ "$(jq -r '.strategy' <<<"$out")" = "dedicated" ] && ok "task.6 standalone Task strategy dedicated" \
  || ko "task.6" "$(jq -r '.strategy' <<<"$out")"

echo ""
echo "=== Summary ==="
echo "Passed: ${PASS}"
echo "Failed: ${FAIL}"
[ "$FAIL" -gt 0 ] && { printf '  - %s\n' "${ERRORS[@]}"; exit 1; }
exit 0
