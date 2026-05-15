#!/usr/bin/env bash
# progress.sh — JSON machine state for in-flight skills (.snap/progress.json).
# Subcommands:
#   start  --skill=X --feature-id=Y               # register skill run (idempotent)
#   step   --skill=X --feature-id=Y --step-num=NN --step-name=NAME --status=STATUS [--note=TEXT] [--extra=JSON]
#   finish --skill=X --feature-id=Y --status=ok|fail
#           # status=ok → purge skill run from in_flight[]
#           # status=fail → keep entry (resume possible)
#   resume --skill=X --feature-id=Y               # stdout: last step status (started|fail|retry) or empty
#   list                                          # stdout: JSON in_flight[]
#
# Exit codes: 0=ok, 1=invalid arg, 2=jq/file error.

set -euo pipefail

PROJECT_ROOT="${SNAP_PROJECT_ROOT:-$(pwd)}"
SCHEMA_VERSION="1.0.0"

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required" >&2; exit 2; }

usage() {
  cat <<EOF
Usage: progress.sh <subcommand> [OPTIONS]

Subcommands:
  start  --skill=X --feature-id=Y
  step   --skill=X --feature-id=Y --step-num=NN --step-name=NAME --status=STATUS [--note=TEXT] [--extra=JSON]
  finish --skill=X --feature-id=Y --status=ok|fail
  resume --skill=X --feature-id=Y
  list

Common:
  --project-root=PATH    Default: \$PWD or \$SNAP_PROJECT_ROOT
  -h, --help

Status values:
  step:   started | ok | fail | skip | retry
  finish: ok | fail

feature-id: NN-kebab or "_global" (init, upgrade, fetch --all).
EOF
}

[ $# -lt 1 ] && { usage >&2; exit 1; }

CMD="$1"; shift
SKILL=""
FEATURE_ID=""
STEP_NUM=""
STEP_NAME=""
STATUS=""
NOTE=""
EXTRA=""

while [ $# -gt 0 ]; do
  case "$1" in
    --project-root=*) PROJECT_ROOT="${1#--project-root=}" ;;
    --skill=*)        SKILL="${1#--skill=}" ;;
    --feature-id=*)   FEATURE_ID="${1#--feature-id=}" ;;
    --step-num=*)     STEP_NUM="${1#--step-num=}" ;;
    --step-name=*)    STEP_NAME="${1#--step-name=}" ;;
    --status=*)       STATUS="${1#--status=}" ;;
    --note=*)         NOTE="${1#--note=}" ;;
    --extra=*)        EXTRA="${1#--extra=}" ;;
    -h|--help)        usage; exit 0 ;;
    *) echo "ERROR: unknown arg: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

SNAP_DIR="${PROJECT_ROOT}/.snap"
PROGRESS_FILE="${SNAP_DIR}/progress.json"

validate_feature_id() {
  if [ "$FEATURE_ID" != "_global" ]; then
    [[ "$FEATURE_ID" =~ ^[0-9]{2}-[a-z0-9][a-z0-9-]*$ ]] || {
      echo "ERROR: --feature-id must be _global or match NN-kebab" >&2
      exit 1
    }
  fi
}

ensure_file() {
  mkdir -p "$SNAP_DIR"
  if [ ! -f "$PROGRESS_FILE" ]; then
    jq -n --arg v "$SCHEMA_VERSION" '{schema_version: $v, in_flight: []}' > "$PROGRESS_FILE"
  fi
}

now() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

write_atomic() {
  local tmp="${PROGRESS_FILE}.tmp.$$"
  cat > "$tmp"
  mv "$tmp" "$PROGRESS_FILE"
}

case "$CMD" in
  start)
    [ -z "$SKILL" ] && { echo "ERROR: --skill required" >&2; exit 1; }
    [ -z "$FEATURE_ID" ] && { echo "ERROR: --feature-id required" >&2; exit 1; }
    validate_feature_id
    ensure_file
    NOW=$(now)
    jq --arg skill "$SKILL" --arg fid "$FEATURE_ID" --arg ts "$NOW" '
      if (.in_flight | map(select(.skill == $skill and .feature_id == $fid)) | length) > 0 then
        .
      else
        .in_flight += [{
          skill: $skill,
          feature_id: $fid,
          started_at: $ts,
          steps: []
        }]
      end
    ' "$PROGRESS_FILE" | write_atomic
    ;;

  step)
    [ -z "$SKILL" ] && { echo "ERROR: --skill required" >&2; exit 1; }
    [ -z "$FEATURE_ID" ] && { echo "ERROR: --feature-id required" >&2; exit 1; }
    [ -z "$STEP_NAME" ] && { echo "ERROR: --step-name required" >&2; exit 1; }
    [ -z "$STATUS" ] && { echo "ERROR: --status required" >&2; exit 1; }
    case "$STATUS" in
      started|ok|fail|skip|retry) ;;
      *) echo "ERROR: --status must be started|ok|fail|skip|retry" >&2; exit 1 ;;
    esac
    validate_feature_id
    ensure_file
    # Auto-start if skill run missing.
    NOW=$(now)
    jq --arg skill "$SKILL" --arg fid "$FEATURE_ID" --arg ts "$NOW" '
      if (.in_flight | map(select(.skill == $skill and .feature_id == $fid)) | length) > 0 then
        .
      else
        .in_flight += [{
          skill: $skill,
          feature_id: $fid,
          started_at: $ts,
          steps: []
        }]
      end
    ' "$PROGRESS_FILE" | write_atomic

    # Build step object.
    STEP_JSON=$(jq -n \
      --arg num "$STEP_NUM" \
      --arg name "$STEP_NAME" \
      --arg status "$STATUS" \
      --arg ts "$NOW" \
      --arg note "$NOTE" \
      --arg extra "$EXTRA" '
      {num: $num, name: $name, status: $status, ts: $ts}
      | (if $note != "" then .note = $note else . end)
      | (if $extra != "" then .extra = ($extra | fromjson) else . end)
    ')

    # Replace last "started" step with same name if exists, else append.
    jq --arg skill "$SKILL" --arg fid "$FEATURE_ID" --argjson step "$STEP_JSON" '
      .in_flight |= map(
        if .skill == $skill and .feature_id == $fid then
          .steps as $s
          | ($s | map(.name == $step.name and .status == "started") | index(true)) as $idx
          | if $idx != null and $step.status != "started" then
              .steps[$idx] = $step
            else
              .steps += [$step]
            end
        else . end
      )
    ' "$PROGRESS_FILE" | write_atomic
    ;;

  finish)
    [ -z "$SKILL" ] && { echo "ERROR: --skill required" >&2; exit 1; }
    [ -z "$FEATURE_ID" ] && { echo "ERROR: --feature-id required" >&2; exit 1; }
    [ -z "$STATUS" ] && { echo "ERROR: --status required (ok|fail)" >&2; exit 1; }
    case "$STATUS" in
      ok|fail) ;;
      *) echo "ERROR: --status must be ok|fail" >&2; exit 1 ;;
    esac
    validate_feature_id
    ensure_file
    if [ "$STATUS" = "ok" ]; then
      # Purge entry — skill ran to terminal step OK.
      jq --arg skill "$SKILL" --arg fid "$FEATURE_ID" '
        .in_flight |= map(select(.skill != $skill or .feature_id != $fid))
      ' "$PROGRESS_FILE" | write_atomic
    fi
    # fail → keep entry as-is for --resume
    ;;

  resume)
    [ -z "$SKILL" ] && { echo "ERROR: --skill required" >&2; exit 1; }
    [ -z "$FEATURE_ID" ] && { echo "ERROR: --feature-id required" >&2; exit 1; }
    validate_feature_id
    [ ! -f "$PROGRESS_FILE" ] && exit 0
    # stdout: last step name with status started|fail|retry, or empty if skill not in_flight.
    jq -r --arg skill "$SKILL" --arg fid "$FEATURE_ID" '
      (.in_flight | map(select(.skill == $skill and .feature_id == $fid)) | first) as $run
      | if $run == null then ""
        else
          ($run.steps | map(select(.status == "started" or .status == "fail" or .status == "retry")) | last) as $s
          | if $s == null then ""
            else "\($s.num)\t\($s.name)\t\($s.status)" end
        end
    ' "$PROGRESS_FILE"
    ;;

  list)
    [ ! -f "$PROGRESS_FILE" ] && { echo '[]'; exit 0; }
    jq '.in_flight' "$PROGRESS_FILE"
    ;;

  -h|--help)
    usage; exit 0
    ;;

  *)
    echo "ERROR: unknown subcommand: $CMD" >&2
    usage >&2
    exit 1
    ;;
esac
