#!/usr/bin/env bash
# update-progress.sh — append step entry to feature progress.md
# Creates progress.md if absent (idempotent header).
#
# Usage:
#   update-progress.sh --feature-id=01-auth --step-num=02 --step-name=vision --status=ok
#   update-progress.sh --feature-id=01-auth --step-num=03 --step-name=features --status=fail --note="user aborted"
#
# Exit codes: 0=ok, 1=invalid arg

set -euo pipefail

PROJECT_ROOT="${ARTYSAN_PROJECT_ROOT:-$(pwd)}"
FEATURE_ID=""
STEP_NUM=""
STEP_NAME=""
STATUS=""
NOTE=""
SKILL=""

usage() {
  cat <<EOF
Usage: update-progress.sh --feature-id=<id> --step-name=<name> --status=<status> [OPTIONS]

Appends a timestamped entry to .claude/product/features/{id}/progress.md.

Options:
  --project-root=PATH     Project root (default: \$PWD)
  --feature-id=NN-kebab   Required. Feature identifier.
  --step-num=NN           Optional. Step number for context.
  --step-name=TEXT        Required. Step name (e.g., "vision", "ticket-push").
  --status=STATUS         Required. ok|fail|skip|retry|started.
  --skill=NAME            Optional. Skill emitting the entry (define|ticket|...).
  --note=TEXT             Optional. Free-form note appended after status.
  -h, --help              Show this help
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --project-root=*) PROJECT_ROOT="${1#--project-root=}" ;;
    --feature-id=*)   FEATURE_ID="${1#--feature-id=}" ;;
    --step-num=*)     STEP_NUM="${1#--step-num=}" ;;
    --step-name=*)    STEP_NAME="${1#--step-name=}" ;;
    --status=*)       STATUS="${1#--status=}" ;;
    --skill=*)        SKILL="${1#--skill=}" ;;
    --note=*)         NOTE="${1#--note=}" ;;
    -h|--help)        usage; exit 0 ;;
    *) echo "ERROR: unknown arg: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

[ -z "$FEATURE_ID" ] && { echo "ERROR: --feature-id required" >&2; exit 1; }
[ -z "$STEP_NAME" ]  && { echo "ERROR: --step-name required" >&2; exit 1; }
[ -z "$STATUS" ]     && { echo "ERROR: --status required" >&2; exit 1; }

if [ "$FEATURE_ID" != "_global" ]; then
  [[ "$FEATURE_ID" =~ ^[0-9]{2}-[a-z0-9][a-z0-9-]*$ ]] || {
    echo "ERROR: --feature-id must be _global or match NN-kebab" >&2
    exit 1
  }
fi

case "$STATUS" in
  ok|fail|skip|retry|started) ;;
  *) echo "ERROR: --status must be ok|fail|skip|retry|started" >&2; exit 1 ;;
esac

if [ "$FEATURE_ID" = "_global" ]; then
  FEATURE_DIR="${PROJECT_ROOT}/.claude/product"
  PROGRESS="${FEATURE_DIR}/progress.md"
else
  FEATURE_DIR="${PROJECT_ROOT}/.claude/product/features/${FEATURE_ID}"
  PROGRESS="${FEATURE_DIR}/progress.md"
fi

mkdir -p "$FEATURE_DIR"

if [ ! -f "$PROGRESS" ]; then
  cat > "$PROGRESS" <<EOF
# Progress — ${FEATURE_ID}

## Decisions & learnings

EOF
fi

NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

prefix=""
[ -n "$SKILL" ]    && prefix="${prefix}/${SKILL}"
[ -n "$STEP_NUM" ] && prefix="${prefix} step-${STEP_NUM}"
prefix="${prefix# }"
prefix="${prefix#/}"

LINE="- [${NOW}]"
[ -n "$prefix" ] && LINE="${LINE} ${prefix}"
LINE="${LINE} ${STEP_NAME} — ${STATUS}"
[ -n "$NOTE" ] && LINE="${LINE}: ${NOTE}"

printf '%s\n' "$LINE" >> "$PROGRESS"

echo "$LINE"
