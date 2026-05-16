#!/usr/bin/env bash
# /develop step-01 Epic filter — story_type=epic → exit code 20 with explicit
# UX message. Other story_types pass through.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE="${ROOT}/skills/_shared/cache-runtime.sh"

PASS=0
FAIL=0
ERRORS=()

ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1 — $2"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

DIR=$(mktemp -d -t snap-dev-epic-XXXXXX)
trap 'trash "$DIR" 2>/dev/null || true' EXIT

run_cache() { bash "$CACHE" "$@" --project-root="$DIR"; }

# step-01 filter inline (mirrors step-01-fetch.md section B).
filter_epic() {
  local ticket_json="$1"
  local story_type
  story_type=$(jq -r '.story_type // ""' <<<"$ticket_json")
  if [ "$story_type" = "epic" ]; then
    cat >&2 <<EOF
ERROR (exit=20): ticket has story_type=epic.
Epic n'est pas une unité de livraison — decompose en User Stories.
EOF
    return 20
  fi
  return 0
}

echo "=== /develop step-01 Epic filter ==="

SUBJECT_ID=$(bash "$CACHE" id-gen --prefix=develop)
run_cache init "$SUBJECT_ID" >/dev/null

# Case A : Epic ticket → exit 20.
EPIC=$(cat <<'JSON'
{"local_id":"t-001","platform_id":"#10","title":"Auth platform",
 "status":"in_progress","story_type":"epic"}
JSON
)
printf '%s' "$EPIC" | run_cache write "$SUBJECT_ID" ticket.json >/dev/null
out_err=$(filter_epic "$EPIC" 2>&1 >/dev/null) ; rc=$?
[ "$rc" = "20" ] && ok "epic.1 Epic refused with rc=20" \
  || ko "epic.1" "rc=$rc"
[[ "$out_err" == *"exit=20"* ]] && ok "epic.2 message carries exit=20 marker" \
  || ko "epic.2" "msg=$out_err"
[[ "$out_err" == *"User Stories"* ]] && ok "epic.3 UX message mentions decomposition" \
  || ko "epic.3" "msg=$out_err"

# Case B : User Story → pass through.
US=$(cat <<'JSON'
{"local_id":"t-002","platform_id":"#11","title":"Email signup",
 "status":"in_progress","story_type":"user-story"}
JSON
)
filter_epic "$US" 2>/dev/null ; rc=$?
[ "$rc" = "0" ] && ok "us.1 user-story passes filter" \
  || ko "us.1" "rc=$rc"

# Case C : Task → pass through.
TASK=$(cat <<'JSON'
{"local_id":"t-003","platform_id":"#12","title":"Add endpoint",
 "status":"in_progress","story_type":"task"}
JSON
)
filter_epic "$TASK" 2>/dev/null ; rc=$?
[ "$rc" = "0" ] && ok "task.1 task passes filter" \
  || ko "task.1" "rc=$rc"

# Case D : Bug → pass through.
BUG=$(cat <<'JSON'
{"local_id":"t-004","platform_id":"#13","title":"Fix crash",
 "status":"in_progress","story_type":"bug"}
JSON
)
filter_epic "$BUG" 2>/dev/null ; rc=$?
[ "$rc" = "0" ] && ok "bug.1 bug passes filter" \
  || ko "bug.1" "rc=$rc"

# Case E : missing story_type → not Epic, passes (defensive — caller catches).
MISSING=$(cat <<'JSON'
{"local_id":"t-005","platform_id":"#14","title":"Unknown","status":"todo"}
JSON
)
filter_epic "$MISSING" 2>/dev/null ; rc=$?
[ "$rc" = "0" ] && ok "miss.1 missing story_type passes (caller validates)" \
  || ko "miss.1" "rc=$rc"

run_cache purge "$SUBJECT_ID" >/dev/null

echo ""
echo "=== Summary ==="
echo "Passed: ${PASS}"
echo "Failed: ${FAIL}"
[ "$FAIL" -gt 0 ] && { printf '  - %s\n' "${ERRORS[@]}"; exit 1; }
exit 0
