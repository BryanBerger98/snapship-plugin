#!/usr/bin/env bash
# sync-push.sh — push local staging → remote, update manifest refs, trash staging.
#
# Pattern :
#   1. Skill génère local staging file (PRD, design asset, ticket payload...).
#   2. Skill appelle sync-push.sh plan → JSON descripteur (path, kind, manifest path).
#   3. Skill push MCP via descriptor docs-adapter / tickets-adapter / figma-helper / etc.
#   4. Si ack OK → sync-push.sh ack    (update manifest, trash staging)
#      Si ack KO → sync-push.sh fail   (sync_status=error, garde staging)
#
# Subcommands:
#   staging-path --feature-id=X --kind=prd|design-gallery|wireframes-gallery|tickets [--screen=NAME]
#       stdout: chemin staging absolu (peut ne pas exister)
#   plan         --feature-id=X --kind=K
#       stdout: JSON {staging_path, manifest_path, kind, exists}
#   ack          --feature-id=X --kind=K --platform=P --url=U
#                [--page-id=P] [--file-key=F] [--project-id=P] [--issue-number=N]
#                [--no-trash]   # garde staging même après ack (debug)
#       Update manifest.refs.<kind> { platform, url, ...ids, synced_at, sync_status=synced }
#       Trash staging file (sauf --no-trash).
#   fail         --feature-id=X --kind=K [--note=TEXT]
#       Update manifest.refs.<kind>.sync_status=error. Garde staging.
#   mark         --feature-id=X --kind=K --status=local-only|pending|synced|dirty|error
#       Update manifest.refs.<kind>.sync_status (helper standalone).
#
# Exit codes: 0=ok, 1=invalid arg, 2=fs/jq err

set -euo pipefail

PROJECT_ROOT="${SNAP_PROJECT_ROOT:-$(pwd)}"
SNAP_DIR="${PROJECT_ROOT}/.snap"
SCHEMA_VERSION="1.0.0"

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required" >&2; exit 2; }

usage() {
  cat <<EOF
Usage: sync-push.sh <subcommand> [OPTIONS]

Subcommands:
  staging-path --feature-id=X --kind=K [--screen=NAME]
  plan         --feature-id=X --kind=K
  ack          --feature-id=X --kind=K --platform=P --url=U [--page-id|--file-key|--project-id|--issue-number=...] [--no-trash]
  fail         --feature-id=X --kind=K [--note=TEXT]
  mark         --feature-id=X --kind=K --status=local-only|pending|synced|dirty|error

Kinds: prd, design-gallery, wireframes-gallery, tickets, design-file

Common: --project-root=PATH, -h
EOF
}

[ $# -lt 1 ] && { usage >&2; exit 1; }

case "$1" in -h|--help) usage; exit 0 ;; esac
CMD="$1"; shift
FEATURE_ID=""
KIND=""
SCREEN=""
PLATFORM=""
URL=""
PAGE_ID=""
FILE_KEY=""
PROJECT_ID=""
ISSUE_NUMBER=""
STATUS=""
NOTE=""
NO_TRASH=false

while [ $# -gt 0 ]; do
  case "$1" in
    --project-root=*)  PROJECT_ROOT="${1#--project-root=}"; SNAP_DIR="${PROJECT_ROOT}/.snap" ;;
    --feature-id=*)    FEATURE_ID="${1#--feature-id=}" ;;
    --kind=*)          KIND="${1#--kind=}" ;;
    --screen=*)        SCREEN="${1#--screen=}" ;;
    --platform=*)      PLATFORM="${1#--platform=}" ;;
    --url=*)           URL="${1#--url=}" ;;
    --page-id=*)       PAGE_ID="${1#--page-id=}" ;;
    --file-key=*)      FILE_KEY="${1#--file-key=}" ;;
    --project-id=*)    PROJECT_ID="${1#--project-id=}" ;;
    --issue-number=*)  ISSUE_NUMBER="${1#--issue-number=}" ;;
    --status=*)        STATUS="${1#--status=}" ;;
    --note=*)          NOTE="${1#--note=}" ;;
    --no-trash)        NO_TRASH=true ;;
    -h|--help)         usage; exit 0 ;;
    *) echo "ERROR: unknown arg: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

[ -z "$FEATURE_ID" ] && { echo "ERROR: --feature-id required" >&2; exit 1; }
[ -z "$KIND" ] && { echo "ERROR: --kind required" >&2; exit 1; }

case "$KIND" in
  prd|design-gallery|wireframes-gallery|tickets|design-file) ;;
  *) echo "ERROR: --kind must be prd|design-gallery|wireframes-gallery|tickets|design-file" >&2; exit 1 ;;
esac

MANIFEST="${SNAP_DIR}/manifests/${FEATURE_ID}.manifest.json"

# Kind → ref key in manifest.
ref_key() {
  case "$1" in
    prd)                 echo "prd" ;;
    design-gallery)      echo "design_gallery" ;;
    wireframes-gallery)  echo "wireframes_gallery" ;;
    tickets)             echo "tickets" ;;
    design-file)         echo "design_file" ;;
  esac
}

# Kind → staging path.
staging_path() {
  case "$1" in
    prd)                 echo "${SNAP_DIR}/PRDs/${FEATURE_ID}.md" ;;
    design-gallery)
      if [ -n "$SCREEN" ]; then
        echo "${SNAP_DIR}/designs/${FEATURE_ID}/${SCREEN}"
      else
        echo "${SNAP_DIR}/designs/${FEATURE_ID}"
      fi ;;
    wireframes-gallery)
      if [ -n "$SCREEN" ]; then
        echo "${SNAP_DIR}/wireframes/${FEATURE_ID}/${SCREEN}"
      else
        echo "${SNAP_DIR}/wireframes/${FEATURE_ID}"
      fi ;;
    tickets)             echo "${SNAP_DIR}/tickets/${FEATURE_ID}.json" ;;
    design-file)         echo "${SNAP_DIR}/designs/${FEATURE_ID}" ;;
  esac
}

now() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

ensure_manifest() {
  if [ ! -f "$MANIFEST" ]; then
    echo "ERROR: manifest missing: ${MANIFEST}" >&2
    echo "Run /snap:define or /snap:fetch first." >&2
    exit 2
  fi
}

write_atomic() {
  local tmp="${MANIFEST}.tmp.$$"
  cat > "$tmp"
  mv "$tmp" "$MANIFEST"
}

REF_KEY=$(ref_key "$KIND")
SPATH=$(staging_path "$KIND")

case "$CMD" in
  staging-path)
    echo "$SPATH"
    ;;

  plan)
    ensure_manifest
    exists="false"
    [ -e "$SPATH" ] && exists="true"
    jq -nc \
      --arg fid "$FEATURE_ID" \
      --arg kind "$KIND" \
      --arg sp "$SPATH" \
      --arg mp "$MANIFEST" \
      --argjson ex "$exists" \
      --arg ref "$REF_KEY" '
      {feature_id:$fid, kind:$kind, ref_key:$ref, staging_path:$sp, manifest_path:$mp, exists:$ex}'
    ;;

  ack)
    [ -z "$PLATFORM" ] && { echo "ERROR: --platform required" >&2; exit 1; }
    [ -z "$URL" ]      && { echo "ERROR: --url required" >&2; exit 1; }
    ensure_manifest
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
          {platform:$plat, url:$url, synced_at:$ts, sync_status:"synced"}
          | if $page != "" then .page_id        = $page else . end
          | if $fkey != "" then .file_key       = $fkey else . end
          | if $pid  != "" then .project_id     = $pid  else . end
          | if $iss  != "" then .issue_number   = $iss  else . end
        )
      | .updated_at = $ts
    ' "$MANIFEST" | write_atomic

    if [ "$NO_TRASH" = false ] && [ -e "$SPATH" ]; then
      trash "$SPATH" 2>/dev/null || true
    fi
    echo "ack:${FEATURE_ID}:${KIND}:synced"
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
    echo "fail:${FEATURE_ID}:${KIND}:error"
    ;;

  mark)
    [ -z "$STATUS" ] && { echo "ERROR: --status required" >&2; exit 1; }
    case "$STATUS" in
      local-only|pending|synced|dirty|error) ;;
      *) echo "ERROR: invalid --status" >&2; exit 1 ;;
    esac
    ensure_manifest
    NOW=$(now)
    jq \
      --arg key "$REF_KEY" \
      --arg st "$STATUS" \
      --arg ts "$NOW" '
      .refs = (.refs // {})
      | .refs[$key] = ((.refs[$key] // {}) + {sync_status:$st})
      | .updated_at = $ts
    ' "$MANIFEST" | write_atomic
    echo "mark:${FEATURE_ID}:${KIND}:${STATUS}"
    ;;

  -h|--help)
    usage; exit 0 ;;

  *)
    echo "ERROR: unknown subcommand: $CMD" >&2
    usage >&2
    exit 1
    ;;
esac
