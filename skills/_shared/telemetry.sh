#!/usr/bin/env bash
# telemetry.sh — append NDJSON event to skills/_shared/telemetry.log
# Auto-rotation: > 10MB → telemetry.log.1 (max 2 files retained: .log + .log.1).
#
# Usage:
#   telemetry.sh --skill=develop --step=03a-execute --status=ok --duration-ms=4521
#   telemetry.sh --skill=qa --step=01-collect --status=fail --severity=major --ticket=AUTH-3
#
# Output: written event JSON on stdout (for piping).
# Exit codes: 0=ok, 1=invalid arg.

set -euo pipefail

SKILL=""
STEP=""
STATUS=""
DURATION_MS=""
TICKET=""
CYCLE=""
SEVERITY=""
FEATURE=""
NOTE=""
LOG_PATH=""

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
  --log-path=PATH         Override default log path
  -h, --help              Show this help

Default log: \$ARTYSAN_TELEMETRY_LOG or skills/_shared/telemetry.log (relative to script dir).
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --skill=*)       SKILL="${1#--skill=}" ;;
    --step=*)        STEP="${1#--step=}" ;;
    --status=*)      STATUS="${1#--status=}" ;;
    --duration-ms=*) DURATION_MS="${1#--duration-ms=}" ;;
    --ticket=*)      TICKET="${1#--ticket=}" ;;
    --feature=*)     FEATURE="${1#--feature=}" ;;
    --cycle=*)       CYCLE="${1#--cycle=}" ;;
    --severity=*)    SEVERITY="${1#--severity=}" ;;
    --note=*)        NOTE="${1#--note=}" ;;
    --log-path=*)    LOG_PATH="${1#--log-path=}" ;;
    -h|--help)       usage; exit 0 ;;
    *) echo "ERROR: unknown arg: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

[ -z "$SKILL" ]  && { echo "ERROR: --skill required" >&2; exit 1; }
[ -z "$STEP" ]   && { echo "ERROR: --step required" >&2; exit 1; }
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

# Resolve log path
if [ -z "$LOG_PATH" ]; then
  if [ -n "${ARTYSAN_TELEMETRY_LOG:-}" ]; then
    LOG_PATH="$ARTYSAN_TELEMETRY_LOG"
  else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    LOG_PATH="${SCRIPT_DIR}/telemetry.log"
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
  --arg note "$NOTE" '
  {ts: $ts, skill: $skill, step: $step, status: $status}
  | if $duration != "" then .duration_ms = ($duration | tonumber) else . end
  | if $ticket   != "" then .ticket = $ticket else . end
  | if $feature  != "" then .feature = $feature else . end
  | if $cycle    != "" then .cycle = ($cycle | tonumber) else . end
  | if $severity != "" then .severity = $severity else . end
  | if $note     != "" then .note = $note else . end
')

printf '%s\n' "$EVENT" >> "$LOG_PATH"
printf '%s\n' "$EVENT"
