#!/usr/bin/env bash
# run-lifecycle-script.sh — execute a workflow lifecycle hook script.
#
# Reads config.lifecycle_scripts.<hook>, resolves to project-root path, and
# executes if present + executable. These hooks are part of the snap
# workflow (≠ Claude Code native hooks).
#
# Behavior:
#   - hook missing in config       → no-op, exit 0
#   - hook path missing on disk    → error, exit 3 (or 0 with --continue-on-error)
#   - hook not executable          → error, exit 3 (same toggle)
#   - hook runs and returns 0      → exit 0
#   - hook runs and returns non-0  → exit script's code (default --strict)
#                                    or exit 0 with --continue-on-error
#
# Environment passed to the script:
#   SNAP_HOOK            e.g., "pre_develop"
#   SNAP_FEATURE_ID      passed via --feature-id (may be empty)
#   SNAP_PROJECT_ROOT    project root
#
# Exit codes:
#   0  ok or no-op
#   1  bad args
#   2  config unreadable
#   3  script missing/not executable (when not --continue-on-error)
#   N  forwarded from the hook script when it fails

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SNAP_PROJECT_ROOT:-$(pwd)}"
HOOK=""
FEATURE_ID=""
CONTINUE="false"
EMIT_JSON="false"

VALID_HOOKS=(pre_define post_define pre_ticket post_ticket pre_wireframe post_wireframe pre_design post_design pre_develop post_develop pre_qa post_qa)

usage() {
  cat <<EOF
Usage: run-lifecycle-script.sh --hook=NAME [OPTIONS]

Runs the lifecycle script configured at config.lifecycle_scripts.<hook>.

Required:
  --hook=NAME              one of: ${VALID_HOOKS[*]}

Options:
  --project-root=PATH      Project root (default: \$PWD or \$SNAP_PROJECT_ROOT)
  --feature-id=ID          Forwarded to the script as SNAP_FEATURE_ID
  --continue-on-error      Treat missing/failing scripts as non-fatal (exit 0)
  --json                   After execution, emit a JSON status summary
  -h, --help               Show this help

Exit codes: 0=ok|no-op, 1=bad args, 2=config error, 3=script missing/not exec,
N=forwarded from hook script.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --hook=*)               HOOK="${1#--hook=}" ;;
    --project-root=*)       PROJECT_ROOT="${1#--project-root=}" ;;
    --feature-id=*)         FEATURE_ID="${1#--feature-id=}" ;;
    --continue-on-error)    CONTINUE="true" ;;
    --json)                 EMIT_JSON="true" ;;
    -h|--help)              usage; exit 0 ;;
    *) echo "ERROR: unknown arg: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

[ -z "$HOOK" ] && { echo "ERROR: --hook required" >&2; exit 1; }

valid=0
for h in "${VALID_HOOKS[@]}"; do
  [ "$h" = "$HOOK" ] && { valid=1; break; }
done
[ "$valid" -eq 1 ] || { echo "ERROR: invalid hook '$HOOK'. Valid: ${VALID_HOOKS[*]}" >&2; exit 1; }

[ -d "$PROJECT_ROOT" ] || { echo "ERROR: project root missing: $PROJECT_ROOT" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required" >&2; exit 1; }

emit_json() {
  local ran="$1" script="$2" exit_code="$3" duration_ms="$4" reason="$5"
  [ "$EMIT_JSON" = "true" ] || return 0
  jq -nc \
    --arg hook    "$HOOK" \
    --arg ran     "$ran" \
    --arg script  "$script" \
    --arg reason  "$reason" \
    --argjson exit_code "$exit_code" \
    --argjson duration_ms "$duration_ms" '
    {hook: $hook, ran: ($ran == "true"), script: $script, exit_code: $exit_code, duration_ms: $duration_ms}
    | if $reason != "" then .reason = $reason else . end
    '
}

# Load config
if [ ! -f "${PROJECT_ROOT}/snap.config.json" ]; then
  emit_json "false" "" "0" "0" "no config"
  exit 0
fi

if [ ! -x "${SCRIPT_DIR}/load-config.sh" ]; then
  echo "ERROR: load-config.sh not executable" >&2
  exit 2
fi

CFG=$(bash "${SCRIPT_DIR}/load-config.sh" --project-root="$PROJECT_ROOT" --no-validate 2>/dev/null) || {
  echo "ERROR: failed to load config" >&2
  exit 2
}

SCRIPT_PATH=$(echo "$CFG" | jq -r --arg h "$HOOK" '.lifecycle_scripts[$h] // ""')

if [ -z "$SCRIPT_PATH" ]; then
  emit_json "false" "" "0" "0" "no script configured"
  exit 0
fi

# Resolve relative paths against project root
case "$SCRIPT_PATH" in
  /*) ABS="$SCRIPT_PATH" ;;
  *)  ABS="${PROJECT_ROOT}/${SCRIPT_PATH}" ;;
esac

if [ ! -f "$ABS" ]; then
  if [ "$CONTINUE" = "true" ]; then
    emit_json "false" "$ABS" "0" "0" "script missing"
    exit 0
  fi
  echo "ERROR: lifecycle script not found: $ABS" >&2
  emit_json "false" "$ABS" "0" "0" "script missing"
  exit 3
fi

if [ ! -x "$ABS" ]; then
  if [ "$CONTINUE" = "true" ]; then
    emit_json "false" "$ABS" "0" "0" "script not executable"
    exit 0
  fi
  echo "ERROR: lifecycle script not executable: $ABS" >&2
  emit_json "false" "$ABS" "0" "0" "script not executable"
  exit 3
fi

# Portable epoch-millis helper: gdate (GNU on macOS) → python3 → seconds*1000.
now_ms() {
  if command -v gdate >/dev/null 2>&1; then
    gdate +%s%3N
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import time;print(int(time.time()*1000))'
  else
    local s; s=$(date +%s)
    echo "$(( s * 1000 ))"
  fi
}

START=$(now_ms)

set +e
SNAP_HOOK="$HOOK" \
SNAP_FEATURE_ID="$FEATURE_ID" \
SNAP_PROJECT_ROOT="$PROJECT_ROOT" \
  "$ABS"
RC=$?
set -e

END=$(now_ms)
DUR=$(( END - START ))
[ "$DUR" -lt 0 ] && DUR=0

emit_json "true" "$ABS" "$RC" "$DUR" ""

if [ "$RC" -ne 0 ] && [ "$CONTINUE" != "true" ]; then
  exit "$RC"
fi
exit 0
