#!/usr/bin/env bash
# sync-fetch.sh — re-pull remote → local staging, update manifest sync state.
#
# Pattern :
#   1. Skill appelle sync-fetch.sh plan → JSON descripteur (ref, staging target).
#   2. Skill pull MCP via descripteur (docs-adapter / figma-helper / tickets-adapter).
#   3. Si ack OK → sync-fetch.sh ack    (write staging file, mark synced)
#      Si ack KO → sync-fetch.sh fail   (sync_status=error)
#   4. check → compare manifest.synced_at vs remote last_edited_time (opt-in, /snap:fetch --check)
#
# Subcommands:
#   plan         --story-id=X --kind=K
#       stdout: JSON {story_id, kind, ref, staging_target, manifest_path}
#       Sortie 1 si refs.<kind> absent du manifest (rien à fetch).
#   ack          --story-id=X --kind=K --content-file=PATH
#                [--platform=P] [--url=U] [--page-id|--file-key|--project-id|--issue-number=...]
#       Copie content-file dans staging target.
#       Update manifest.refs.<kind> { synced_at, sync_status=synced } (+ optional ids).
#   fail         --story-id=X --kind=K [--note=TEXT]
#       Mark sync_status=error.
#   check-mark   --story-id=X --kind=K --remote-edited=TIMESTAMP
#       Compare manifest.refs.<kind>.synced_at vs remote-edited.
#       Si remote > local → mark sync_status=dirty (suggère fetch).
#
# Exit codes: 0=ok, 1=invalid arg / ref absent, 2=fs/jq err

set -euo pipefail

PROJECT_ROOT="${SNAP_PROJECT_ROOT:-$(pwd)}"
SNAP_DIR="${PROJECT_ROOT}/.snap"

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required" >&2; exit 2; }

usage() {
  cat <<EOF
Usage: sync-fetch.sh <subcommand> [OPTIONS]

Subcommands:
  plan         --story-id=X --kind=K
  ack          --story-id=X --kind=K --content-file=PATH [--platform=P --url=U ...ids]
  fail         --story-id=X --kind=K [--note=TEXT]
  check-mark   --story-id=X --kind=K --remote-edited=TIMESTAMP

Kinds: prd, design-gallery, wireframes-gallery, tickets, design-file

Common: --project-root=PATH, -h
EOF
}

[ $# -lt 1 ] && { usage >&2; exit 1; }

case "$1" in -h|--help) usage; exit 0 ;; esac
CMD="$1"; shift
FEATURE_ID=""
KIND=""
CONTENT_FILE=""
PLATFORM=""
URL=""
PAGE_ID=""
FILE_KEY=""
PROJECT_ID=""
ISSUE_NUMBER=""
NOTE=""
REMOTE_EDITED=""

while [ $# -gt 0 ]; do
  case "$1" in
    --project-root=*)  PROJECT_ROOT="${1#--project-root=}"; SNAP_DIR="${PROJECT_ROOT}/.snap" ;;
    --story-id=*)    FEATURE_ID="${1#--story-id=}" ;;
    --kind=*)          KIND="${1#--kind=}" ;;
    --content-file=*)  CONTENT_FILE="${1#--content-file=}" ;;
    --platform=*)      PLATFORM="${1#--platform=}" ;;
    --url=*)           URL="${1#--url=}" ;;
    --page-id=*)       PAGE_ID="${1#--page-id=}" ;;
    --file-key=*)      FILE_KEY="${1#--file-key=}" ;;
    --project-id=*)    PROJECT_ID="${1#--project-id=}" ;;
    --issue-number=*)  ISSUE_NUMBER="${1#--issue-number=}" ;;
    --note=*)          NOTE="${1#--note=}" ;;
    --remote-edited=*) REMOTE_EDITED="${1#--remote-edited=}" ;;
    -h|--help)         usage; exit 0 ;;
    *) echo "ERROR: unknown arg: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

[ -z "$FEATURE_ID" ] && { echo "ERROR: --story-id required" >&2; exit 1; }
[ -z "$KIND" ] && { echo "ERROR: --kind required" >&2; exit 1; }

case "$KIND" in
  prd|design-gallery|wireframes-gallery|tickets|design-file) ;;
  *) echo "ERROR: --kind must be prd|design-gallery|wireframes-gallery|tickets|design-file" >&2; exit 1 ;;
esac

MANIFEST="${SNAP_DIR}/manifests/${FEATURE_ID}.manifest.json"

ref_key() {
  case "$1" in
    prd) echo "prd" ;;
    design-gallery) echo "design_gallery" ;;
    wireframes-gallery) echo "wireframes_gallery" ;;
    tickets) echo "tickets" ;;
    design-file) echo "design_file" ;;
  esac
}

staging_target() {
  case "$1" in
    prd)                 echo "${SNAP_DIR}/PRDs/${FEATURE_ID}.md" ;;
    design-gallery)      echo "${SNAP_DIR}/designs/${FEATURE_ID}/gallery.md" ;;
    wireframes-gallery)  echo "${SNAP_DIR}/wireframes/${FEATURE_ID}/gallery.md" ;;
    tickets)             echo "${SNAP_DIR}/tickets/${FEATURE_ID}.json" ;;
    design-file)         echo "${SNAP_DIR}/designs/${FEATURE_ID}/design.txt" ;;
  esac
}

now() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

ensure_manifest() {
  if [ ! -f "$MANIFEST" ]; then
    echo "ERROR: manifest missing: ${MANIFEST}" >&2
    exit 2
  fi
}

write_atomic() {
  local tmp="${MANIFEST}.tmp.$$"
  cat > "$tmp"
  mv "$tmp" "$MANIFEST"
}

REF_KEY=$(ref_key "$KIND")
STARGET=$(staging_target "$KIND")

case "$CMD" in
  plan)
    ensure_manifest
    REF=$(jq -c --arg key "$REF_KEY" '.refs[$key] // null' "$MANIFEST")
    if [ "$REF" = "null" ]; then
      echo "ERROR: refs.${REF_KEY} absent du manifest" >&2
      exit 1
    fi
    jq -nc \
      --arg fid "$FEATURE_ID" \
      --arg kind "$KIND" \
      --arg key "$REF_KEY" \
      --arg st "$STARGET" \
      --arg mp "$MANIFEST" \
      --argjson ref "$REF" '
      {story_id:$fid, kind:$kind, ref_key:$key, ref:$ref, staging_target:$st, manifest_path:$mp}'
    ;;

  ack)
    [ -z "$CONTENT_FILE" ] && { echo "ERROR: --content-file required" >&2; exit 1; }
    [ -f "$CONTENT_FILE" ] || { echo "ERROR: content file not found: $CONTENT_FILE" >&2; exit 2; }
    ensure_manifest
    mkdir -p "$(dirname "$STARGET")"
    cp "$CONTENT_FILE" "$STARGET"
    NOW=$(now)
    jq \
      --arg key "$REF_KEY" \
      --arg plat "$PLATFORM" \
      --arg url "$URL" \
      --arg page "$PAGE_ID" \
      --arg fkey "$FILE_KEY" \
      --arg pid "$PROJECT_ID" \
      --arg iss "$ISSUE_NUMBER" \
      --arg ts "$NOW" '
      .refs = (.refs // {})
      | .refs[$key] = (
          (.refs[$key] // {})
          + {synced_at:$ts, sync_status:"synced"}
          | if $plat != "" then .platform = $plat else . end
          | if $url  != "" then .url      = $url  else . end
          | if $page != "" then .page_id  = $page else . end
          | if $fkey != "" then .file_key = $fkey else . end
          | if $pid  != "" then .project_id = $pid else . end
          | if $iss  != "" then .issue_number = $iss else . end
        )
      | .updated_at = $ts
    ' "$MANIFEST" | write_atomic
    echo "fetch-ack:${FEATURE_ID}:${KIND}:synced:${STARGET}"
    ;;

  fail)
    ensure_manifest
    NOW=$(now)
    jq \
      --arg key "$REF_KEY" \
      --arg ts "$NOW" \
      --arg note "$NOTE" '
      .refs = (.refs // {})
      | .refs[$key] = ((.refs[$key] // {}) + {sync_status:"error"})
      | (if $note != "" then .refs[$key].error_note = $note else . end)
      | .updated_at = $ts
    ' "$MANIFEST" | write_atomic
    echo "fetch-fail:${FEATURE_ID}:${KIND}"
    ;;

  check-mark)
    [ -z "$REMOTE_EDITED" ] && { echo "ERROR: --remote-edited required" >&2; exit 1; }
    ensure_manifest
    LOCAL_TS=$(jq -r --arg key "$REF_KEY" '.refs[$key].synced_at // ""' "$MANIFEST")
    if [ -z "$LOCAL_TS" ]; then
      echo "skip:no-local-synced_at"
      exit 0
    fi
    # String compare ISO-8601 works lexicographically when same TZ (Z).
    if [[ "$REMOTE_EDITED" > "$LOCAL_TS" ]]; then
      jq \
        --arg key "$REF_KEY" '
        .refs = (.refs // {})
        | .refs[$key] = ((.refs[$key] // {}) + {sync_status:"dirty"})
      ' "$MANIFEST" | write_atomic
      echo "dirty:${FEATURE_ID}:${KIND}:remote=${REMOTE_EDITED}:local=${LOCAL_TS}"
    else
      echo "up-to-date:${FEATURE_ID}:${KIND}"
    fi
    ;;

  -h|--help)
    usage; exit 0 ;;

  *)
    echo "ERROR: unknown subcommand: $CMD" >&2
    usage >&2
    exit 1
    ;;
esac
