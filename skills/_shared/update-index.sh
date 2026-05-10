#!/usr/bin/env bash
# update-index.sh — idempotent edit of features table in .claude/product/index.md
# Existing row updated in-place (only provided fields override; others preserved).
# Missing row appended after last data row of features table.
#
# Usage:
#   update-index.sh --feature-id=01-auth --state=developed
#   update-index.sh --feature-id=01-auth --feature-name="Auth" --tickets="8 (JIRA AUTH-1..8)"
#
# Exit codes: 0=ok, 1=invalid arg / index.md missing

set -euo pipefail

PROJECT_ROOT="${SNAP_PROJECT_ROOT:-$(pwd)}"
FEATURE_ID=""
FEATURE_NAME=""
STATE=""
AFFINE=""
TICKETS=""
WIREFRAMES=""
DEV=""

usage() {
  cat <<EOF
Usage: update-index.sh --feature-id=<id> [OPTIONS]

Idempotently updates feature row in .claude/product/index.md.
If row absent, appends. If present, only provided fields override; others preserved.

Options:
  --project-root=PATH     Project root (default: \$PWD)
  --feature-id=NN-kebab   Required. Feature identifier.
  --feature-name=TEXT     Display name (column "Nom")
  --state=STATE           defined|ticketed|wireframed|developed|qa-validated
  --affine=TEXT           AFFiNE column (e.g., "[PRD](affine://...)")
  --tickets=TEXT          Tickets column (e.g., "8 (JIRA AUTH-1..8)")
  --wireframes=TEXT       Wireframes column
  --dev=TEXT              Dev progress (e.g., "8/8")
  -h, --help              Show this help

Note: avoid '|' in cell values (breaks markdown table parsing).
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --project-root=*) PROJECT_ROOT="${1#--project-root=}" ;;
    --feature-id=*)   FEATURE_ID="${1#--feature-id=}" ;;
    --feature-name=*) FEATURE_NAME="${1#--feature-name=}" ;;
    --state=*)        STATE="${1#--state=}" ;;
    --affine=*)       AFFINE="${1#--affine=}" ;;
    --tickets=*)      TICKETS="${1#--tickets=}" ;;
    --wireframes=*)   WIREFRAMES="${1#--wireframes=}" ;;
    --dev=*)          DEV="${1#--dev=}" ;;
    -h|--help)        usage; exit 0 ;;
    *) echo "ERROR: unknown arg: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

[ -z "$FEATURE_ID" ] && { echo "ERROR: --feature-id required" >&2; exit 1; }
[[ "$FEATURE_ID" =~ ^[0-9]{2}-[a-z0-9][a-z0-9-]*$ ]] || {
  echo "ERROR: --feature-id must match NN-kebab" >&2
  exit 1
}

if [ -n "$STATE" ]; then
  case "$STATE" in
    defined|ticketed|wireframed|developed|qa-validated) ;;
    *) echo "ERROR: invalid state '${STATE}'" >&2; exit 1 ;;
  esac
fi

INDEX="${PROJECT_ROOT}/.claude/product/index.md"
[ -f "$INDEX" ] || {
  echo "ERROR: index.md not found at ${INDEX}. Run setup-product-dir.sh first." >&2
  exit 1
}

trim() {
  local v="$1"
  v="${v#"${v%%[![:space:]]*}"}"
  v="${v%"${v##*[![:space:]]}"}"
  printf '%s' "$v"
}

existing=$(grep -E "^\| ${FEATURE_ID} +\|" "$INDEX" || true)

if [ -n "$existing" ]; then
  IFS='|' read -ra cells <<< "$existing"
  ex_name=$(trim "${cells[2]:-}")
  ex_state=$(trim "${cells[3]:-}")
  ex_affine=$(trim "${cells[4]:-}")
  ex_tickets=$(trim "${cells[5]:-}")
  ex_wf=$(trim "${cells[6]:-}")
  ex_dev=$(trim "${cells[7]:-}")
else
  ex_name="-"
  ex_state="-"
  ex_affine="-"
  ex_tickets="-"
  ex_wf="-"
  ex_dev="-"
fi

NEW_NAME="${FEATURE_NAME:-$ex_name}"
NEW_STATE="${STATE:-$ex_state}"
NEW_AFFINE="${AFFINE:-$ex_affine}"
NEW_TICKETS="${TICKETS:-$ex_tickets}"
NEW_WF="${WIREFRAMES:-$ex_wf}"
NEW_DEV="${DEV:-$ex_dev}"

NEW_ROW="| ${FEATURE_ID} | ${NEW_NAME} | ${NEW_STATE} | ${NEW_AFFINE} | ${NEW_TICKETS} | ${NEW_WF} | ${NEW_DEV} |"

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

awk -v fid="$FEATURE_ID" -v newrow="$NEW_ROW" '
BEGIN { in_table=0; replaced=0 }
/^\| feature_id \|/ { in_table=1; print; next }
in_table==1 && /^\| -+ \|/ { print; next }
in_table==1 && /^\| / {
  line=$0
  sub(/^\| /, "", line)
  rid=line
  sub(/ \|.*$/, "", rid)
  if (rid == fid) {
    print newrow
    replaced=1
  } else {
    print
  }
  next
}
in_table==1 && !/^\| / {
  if (!replaced) {
    print newrow
    replaced=1
  }
  in_table=0
  print
  next
}
{ print }
END {
  if (in_table==1 && !replaced) print newrow
}
' "$INDEX" > "$TMP"

mv "$TMP" "$INDEX"

echo "$NEW_ROW"
