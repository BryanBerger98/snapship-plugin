#!/usr/bin/env bash
# setup-snap-dir.sh — idempotent init of .snap/ workspace.
# Creates the catalog dirs (manifests, PRDs, designs, wireframes, tickets, queues,
# .doc-import) and bootstrap files (manifest, _taxonomy.json, progress.json).
# All operations idempotent: existing files left intact.
#
# Usage:
#   setup-snap-dir.sh                                              # init root only
#   setup-snap-dir.sh --story-id=01-auth --story-name="Auth"   # also init manifest
#
# Exit codes:
#   0 = success
#   1 = invalid arg / story_id format / write error

set -euo pipefail

PROJECT_ROOT="${SNAP_PROJECT_ROOT:-$(pwd)}"
FEATURE_ID=""
FEATURE_NAME=""
LANG_DEFAULT=""
GREEN_FIELD=""
SCHEMA_VERSION="1.0.0"

usage() {
  cat <<EOF
Usage: setup-snap-dir.sh [OPTIONS]

Idempotently creates .snap/ scaffolding (v1.0).

Options:
  --project-root=PATH       Project root (default: \$PWD)
  --story-id=NN-kebab     Also init manifests/{id}.manifest.json
  --story-name=TEXT       Required with --story-id
  --lang=fr|en              Optional, written to manifest
  --green-field=true|false  Optional, written to manifest
  -h, --help                Show this help
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --project-root=*)  PROJECT_ROOT="${1#--project-root=}" ;;
    --story-id=*)    FEATURE_ID="${1#--story-id=}" ;;
    --story-name=*)  FEATURE_NAME="${1#--story-name=}" ;;
    --lang=*)          LANG_DEFAULT="${1#--lang=}" ;;
    --green-field=*)   GREEN_FIELD="${1#--green-field=}" ;;
    -h|--help)         usage; exit 0 ;;
    *) echo "ERROR: unknown arg: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required" >&2; exit 1; }

SNAP_DIR="${PROJECT_ROOT}/.snap"
MANIFESTS_DIR="${SNAP_DIR}/manifests"
TAXONOMY="${MANIFESTS_DIR}/_taxonomy.json"
PROGRESS_FILE="${SNAP_DIR}/progress.json"

mkdir -p "$MANIFESTS_DIR"
mkdir -p "${SNAP_DIR}/PRDs"
mkdir -p "${SNAP_DIR}/designs"
mkdir -p "${SNAP_DIR}/wireframes"
mkdir -p "${SNAP_DIR}/tickets"
mkdir -p "${SNAP_DIR}/queues"
mkdir -p "${SNAP_DIR}/.doc-import/cache"

# --- _taxonomy.json scaffold ---
if [ ! -f "$TAXONOMY" ]; then
  jq -n --arg v "$SCHEMA_VERSION" '{
    schema_version: $v,
    workspace: {},
    domains: {},
    journeys: {}
  }' > "$TAXONOMY"
fi

# --- progress.json scaffold (gitignored) ---
if [ ! -f "$PROGRESS_FILE" ]; then
  jq -n --arg v "$SCHEMA_VERSION" '{schema_version: $v, in_flight: []}' > "$PROGRESS_FILE"
fi

# --- Per-feature manifest (optional) ---
if [ -n "$FEATURE_ID" ]; then
  if ! [[ "$FEATURE_ID" =~ ^[0-9]{2}-[a-z0-9][a-z0-9-]*$ ]]; then
    echo "ERROR: story_id must match NN-kebab (e.g., 01-auth), got: ${FEATURE_ID}" >&2
    exit 1
  fi

  if [ -z "$FEATURE_NAME" ]; then
    echo "ERROR: --story-name required with --story-id" >&2
    exit 1
  fi

  MANIFEST="${MANIFESTS_DIR}/${FEATURE_ID}.manifest.json"
  if [ ! -f "$MANIFEST" ]; then
    NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    jq -n \
      --arg v "$SCHEMA_VERSION" \
      --arg fid "$FEATURE_ID" \
      --arg fname "$FEATURE_NAME" \
      --arg now "$NOW" \
      --arg lang "$LANG_DEFAULT" \
      --arg gf "$GREEN_FIELD" '
      {
        schema_version: $v,
        story_id: $fid,
        story_name: $fname,
        state: "defined",
        created_at: $now,
        refs: {}
      }
      | if $lang != "" then .lang = $lang else . end
      | if $gf == "true" then .green_field = true
        elif $gf == "false" then .green_field = false
        else . end
    ' > "$MANIFEST"
  fi
fi

echo "$SNAP_DIR"
