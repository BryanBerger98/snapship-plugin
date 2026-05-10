#!/usr/bin/env bash
# setup-product-dir.sh — idempotent init of .claude/product/
# Creates: index.md, features/, optionally features/{id}/{meta.json, progress.md, wireframes/}.
# All operations idempotent: existing files left intact.
#
# Usage:
#   setup-product-dir.sh                                              # init root only
#   setup-product-dir.sh --feature-id=01-auth --feature-name="Auth"   # also init feature
#
# Exit codes:
#   0 = success
#   1 = invalid arg / feature_id format / write error

set -euo pipefail

PROJECT_ROOT="${SNAP_PROJECT_ROOT:-$(pwd)}"
FEATURE_ID=""
FEATURE_NAME=""
LANG_DEFAULT=""
GREEN_FIELD=""

usage() {
  cat <<EOF
Usage: setup-product-dir.sh [OPTIONS]

Idempotently creates .claude/product/ scaffolding.

Options:
  --project-root=PATH       Project root (default: \$PWD)
  --feature-id=NN-kebab     Also init features/{id}/ subdir
  --feature-name=TEXT       Required with --feature-id (used in meta.json)
  --lang=fr|en              Optional, written to meta.json
  --green-field=true|false  Optional, written to meta.json
  -h, --help                Show this help
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --project-root=*)  PROJECT_ROOT="${1#--project-root=}" ;;
    --feature-id=*)    FEATURE_ID="${1#--feature-id=}" ;;
    --feature-name=*)  FEATURE_NAME="${1#--feature-name=}" ;;
    --lang=*)          LANG_DEFAULT="${1#--lang=}" ;;
    --green-field=*)   GREEN_FIELD="${1#--green-field=}" ;;
    -h|--help)         usage; exit 0 ;;
    *) echo "ERROR: unknown arg: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required" >&2; exit 1; }

PRODUCT_DIR="${PROJECT_ROOT}/.claude/product"
INDEX_FILE="${PRODUCT_DIR}/index.md"
FEATURES_DIR="${PRODUCT_DIR}/features"

mkdir -p "$FEATURES_DIR"

# --- Index scaffold ---
if [ ! -f "$INDEX_FILE" ]; then
  cat > "$INDEX_FILE" <<'EOF'
# Product Index

## Features

| feature_id | Nom | État | AFFiNE | Tickets | Wireframes | Dev |
| ---------- | --- | ---- | ------ | ------- | ---------- | --- |

## Plateforme tickets

- Type: -
- Last sync: -

## Documentation

- Platform: -
- Workspace: -
- Root page: -
EOF
fi

# --- Feature scaffold (optional) ---
if [ -n "$FEATURE_ID" ]; then
  if ! [[ "$FEATURE_ID" =~ ^[0-9]{2}-[a-z0-9][a-z0-9-]*$ ]]; then
    echo "ERROR: feature_id must match NN-kebab (e.g., 01-auth), got: ${FEATURE_ID}" >&2
    exit 1
  fi

  if [ -z "$FEATURE_NAME" ]; then
    echo "ERROR: --feature-name required with --feature-id" >&2
    exit 1
  fi

  FEATURE_DIR="${FEATURES_DIR}/${FEATURE_ID}"
  mkdir -p "${FEATURE_DIR}/wireframes"

  META="${FEATURE_DIR}/meta.json"
  if [ ! -f "$META" ]; then
    NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    jq -n \
      --arg fid "$FEATURE_ID" \
      --arg fname "$FEATURE_NAME" \
      --arg now "$NOW" \
      --arg lang "$LANG_DEFAULT" \
      --arg gf "$GREEN_FIELD" '
      {
        feature_id: $fid,
        feature_name: $fname,
        state: "defined",
        created_at: $now
      }
      | if $lang != "" then .lang = $lang else . end
      | if $gf == "true" then .green_field = true
        elif $gf == "false" then .green_field = false
        else . end
    ' > "$META"
  fi

  PROGRESS="${FEATURE_DIR}/progress.md"
  if [ ! -f "$PROGRESS" ]; then
    cat > "$PROGRESS" <<EOF
# Progress — ${FEATURE_ID} (${FEATURE_NAME})

## Decisions & learnings

EOF
  fi
fi

echo "$PRODUCT_DIR"
