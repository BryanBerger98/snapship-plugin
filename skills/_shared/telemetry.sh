#!/usr/bin/env bash
# telemetry.sh — append NDJSON event to .snap/telemetry.ndjson (per-project).
# Auto-rotation: > 10MB → telemetry.ndjson.1 (max 2 files retained).
#
# Usage:
#   telemetry.sh --skill=develop --step=03a-execute --status=ok --duration-ms=4521
#   telemetry.sh log --skill=upgrade --step-num=01 --step-name=confirm --status=ok
#   telemetry.sh --skill=qa --step=01-collect --status=fail --severity=major --ticket=AUTH-3
#
# Both invocation forms accepted (the bare "log" subcommand is a no-op shim).
# When --step-num + --step-name are passed, --step is derived as "NN-name".
#
# Output: written event JSON on stdout (for piping).
# Exit codes: 0=ok, 1=invalid arg.

set -euo pipefail

# Optional "log" subcommand shim (silently consumed)
if [ "${1:-}" = "log" ]; then shift; fi

SKILL=""
STEP=""
STEP_NUM=""
STEP_NAME=""
STATUS=""
DURATION_MS=""
TICKET=""
CYCLE=""
SEVERITY=""
FEATURE=""
NOTE=""
EXTRA=""
LOG_PATH=""
PROJECT_ROOT="${SNAP_PROJECT_ROOT:-$(pwd)}"

usage() {
  cat <<EOF
Usage: telemetry.sh --skill=NAME --step=ID --status=STATUS [OPTIONS]

Appends a single NDJSON event to telemetry.log.

Required:
  --skill=NAME            Skill emitting the event (define|ticket|wireframe|develop|qa)
  --step=ID               Step identifier (e.g., 02-vision, 03a-execute)
  --status=STATUS         ok|fail|skip|retry|started

Optional:
  --duration-ms=N         Milliseconds elapsed
  --ticket=ID             Ticket identifier (platform-specific)
  --feature=ID            Feature identifier (NN-kebab)
  --cycle=N               Review/QA cycle number
  --severity=LEVEL        info|minor|major|critical (when applicable)
  --note=TEXT             Free-form note
  --extra=JSON            JSON object merged into event as .extra
  --log-path=PATH         Override default log path
  -h, --help              Show this help

Default log: \$SNAP_TELEMETRY_LOG or skills/_shared/telemetry.log (relative to script dir).
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --skill=*)        SKILL="${1#--skill=}" ;;
    --step=*)         STEP="${1#--step=}" ;;
    --step-num=*)     STEP_NUM="${1#--step-num=}" ;;
    --step-name=*)    STEP_NAME="${1#--step-name=}" ;;
    --status=*)       STATUS="${1#--status=}" ;;
    --duration-ms=*)  DURATION_MS="${1#--duration-ms=}" ;;
    --ticket=*)       TICKET="${1#--ticket=}" ;;
    --feature=*|--feature-id=*) FEATURE="${1#*=}" ;;
    --cycle=*)        CYCLE="${1#--cycle=}" ;;
    --severity=*)     SEVERITY="${1#--severity=}" ;;
    --note=*)         NOTE="${1#--note=}" ;;
    --extra=*)        EXTRA="${1#--extra=}" ;;
    --log-path=*)     LOG_PATH="${1#--log-path=}" ;;
    --project-root=*) PROJECT_ROOT="${1#--project-root=}" ;;
    -h|--help)        usage; exit 0 ;;
    *) echo "ERROR: unknown arg: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

# Compose --step from --step-num/--step-name if --step not given
if [ -z "$STEP" ] && [ -n "$STEP_NUM" ] && [ -n "$STEP_NAME" ]; then
  STEP="${STEP_NUM}-${STEP_NAME}"
elif [ -z "$STEP" ] && [ -n "$STEP_NAME" ]; then
  STEP="$STEP_NAME"
fi

[ -z "$SKILL" ]  && { echo "ERROR: --skill required" >&2; exit 1; }
[ -z "$STEP" ]   && { echo "ERROR: --step or --step-num+--step-name required" >&2; exit 1; }
[ -z "$STATUS" ] && { echo "ERROR: --status required" >&2; exit 1; }

case "$STATUS" in
  ok|fail|skip|retry|started) ;;
  *) echo "ERROR: --status must be ok|fail|skip|retry|started" >&2; exit 1 ;;
esac

if [ -n "$SEVERITY" ]; then
  case "$SEVERITY" in
    info|minor|major|critical) ;;
    *) echo "ERROR: --severity must be info|minor|major|critical" >&2; exit 1 ;;
  esac
fi

if [ -n "$DURATION_MS" ] && ! [[ "$DURATION_MS" =~ ^[0-9]+$ ]]; then
  echo "ERROR: --duration-ms must be integer" >&2
  exit 1
fi

if [ -n "$CYCLE" ] && ! [[ "$CYCLE" =~ ^[0-9]+$ ]]; then
  echo "ERROR: --cycle must be integer" >&2
  exit 1
fi

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required" >&2; exit 1; }

# Resolve log path: --log-path > $SNAP_TELEMETRY_LOG > $PROJECT_ROOT/.snap/telemetry.ndjson
if [ -z "$LOG_PATH" ]; then
  if [ -n "${SNAP_TELEMETRY_LOG:-}" ]; then
    LOG_PATH="$SNAP_TELEMETRY_LOG"
  else
    LOG_PATH="${PROJECT_ROOT}/.snap/telemetry.ndjson"
  fi
fi

mkdir -p "$(dirname "$LOG_PATH")"

# Rotation: > 10MB → .log.1 (overwrite previous .1)
MAX_BYTES=$((10 * 1024 * 1024))
if [ -f "$LOG_PATH" ]; then
  size=$(wc -c < "$LOG_PATH" | tr -d ' ')
  if [ "$size" -gt "$MAX_BYTES" ]; then
    mv -f "$LOG_PATH" "${LOG_PATH}.1"
  fi
fi

NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Validate --extra is JSON object if provided; normalize empty → null.
if [ -n "$EXTRA" ]; then
  echo "$EXTRA" | jq -e 'type == "object"' >/dev/null 2>&1 || {
    echo "ERROR: --extra must be a JSON object" >&2; exit 1;
  }
else
  EXTRA="null"
fi

EVENT=$(jq -nc \
  --arg ts "$NOW" \
  --arg skill "$SKILL" \
  --arg step "$STEP" \
  --arg status "$STATUS" \
  --arg duration "$DURATION_MS" \
  --arg ticket "$TICKET" \
  --arg feature "$FEATURE" \
  --arg cycle "$CYCLE" \
  --arg severity "$SEVERITY" \
  --arg note "$NOTE" \
  --argjson extra "$EXTRA" '
  {ts: $ts, skill: $skill, step: $step, status: $status}
  | if $duration != "" then .duration_ms = ($duration | tonumber) else . end
  | if $ticket   != "" then .ticket = $ticket else . end
  | if $feature  != "" then .feature = $feature else . end
  | if $cycle    != "" then .cycle = ($cycle | tonumber) else . end
  | if $severity != "" then .severity = $severity else . end
  | if $note     != "" then .note = $note else . end
  | if $extra    != null then .extra = $extra else . end
')

printf '%s\n' "$EVENT" >> "$LOG_PATH"
printf '%s\n' "$EVENT"
