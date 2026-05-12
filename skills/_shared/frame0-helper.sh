#!/usr/bin/env bash
# frame0-helper.sh — wrapper for batch operations on the Frame0 MCP server.
#
# Frame0 is MCP-only. The helper emits MCP descriptors on stdout (exit 10)
# for the calling skill to dispatch. The dispatcher converts {action,params}
# into the concrete Frame0 MCP tool call.
#
# Actions:
#   create-page    --title (--parent-id)
#   get-page       --page-id
#   update-page    --page-id (--title)
#   delete-page    --page-id
#   list-pages     --query (--limit, default 20)
#   add-shapes     --page-id --shapes (JSON array of shape objects)
#   export-page    --page-id --output-path (--format png|svg|pdf, --scale 1|2|3)
#                  DEPRECATED for use from the Claude Code harness: Frame0 MCP
#                  returns the export as an `image` content block whose base64
#                  data is rendered visually and never surfaces as text — there
#                  is no way to pipe it back into `save-export`. Use
#                  `export-png` instead, which bypasses MCP and calls Frame0's
#                  local HTTP API (`http://localhost:<api-port>/execute_command`).
#                  Kept for library/manual use only.
#   export-png     --page-id --output-path (--format png|jpeg|webp, --api-port N)
#                  Local-only — bypasses MCP. POSTs `file:export-image` to the
#                  Frame0 desktop HTTP API, decodes the returned base64, writes
#                  the asset to --output-path. Requires Frame0 desktop running.
#                  API port defaults to 58320 if --api-port omitted. The base URL
#                  can be overridden for tests via $SNAP_FRAME0_API_BASE; the entire
#                  HTTP call can be stubbed via $SNAP_FRAME0_MOCK_RESPONSE_FILE
#                  (path to JSON body).
#   save-export    --output-path --base64-data DATA|--base64-file PATH|--base64-stdin
#                  Decode an arbitrary base64 payload (e.g. captured from a
#                  Frame0 response) and write the binary asset to --output-path.
#                  Strips a `data:image/...;base64,` prefix when present.
#                  Local-only — never emits an MCP descriptor.
#
# Helper context-agnostic depuis v0.5: ne lit aucune configuration projet.
# Les params (--format/--scale/--api-port) sont passés explicitement par le skill.
# Défauts internes appliqués si arg absent: format=png, scale=2, api_port=58320.
# export-png ignore --scale (l'API HTTP Frame0 n'a pas de paramètre scale).
#
# Output JSON shapes:
#   mcp:  {"ok":false,"mode":"mcp","reason":"mcp_required","descriptor":{...}}  exit 10
#   dry:  {"ok":true,"mode":"dry-run","action":...,"result":{...}}              exit 0
#   err:  {"ok":false,"error":"..."}                                            exit 1|2

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SNAP_PROJECT_ROOT:-$(pwd)}"
ACTION=""
PAGE_ID=""
PARENT_ID=""
TITLE=""
SHAPES_JSON=""
SHAPES_FILE=""
OUTPUT_PATH=""
EXPORT_FORMAT=""
EXPORT_SCALE=""
BASE64_DATA=""
BASE64_FILE=""
BASE64_STDIN="false"
API_PORT=""
QUERY=""
LIMIT="20"
DRY_RUN="${SNAP_DRY_RUN:-false}"

usage() {
  cat <<EOF
Usage: frame0-helper.sh --action=ACTION [OPTIONS]

Actions:
  create-page    --title (--parent-id)
  get-page       --page-id
  update-page    --page-id (--title)
  delete-page    --page-id
  list-pages     --query (--limit, default 20)
  add-shapes     --page-id --shapes JSON|@file
  export-page    --page-id --output-path (--format, --scale)         [DEPRECATED — see export-png]
  export-png     --page-id --output-path (--format png|jpeg|webp, --api-port N)
  save-export    --output-path --base64-data DATA|--base64-file PATH|--base64-stdin

Options:
  --project-root=PATH      Project root (default: \$PWD)
  --page-id=ID
  --parent-id=ID
  --title=TEXT
  --shapes=JSON            JSON array of shape descriptors
  --shapes-file=PATH       Read shapes JSON from file
  --output-path=PATH       Where to save exported asset
  --format=png|svg|pdf     Export format (config default: png)
  --scale=1|2|3            Export scale (config default: 2)
  --base64-data=DATA       Base64 payload from Frame0 MCP export_page result
  --base64-file=PATH       Read base64 payload from a file
  --base64-stdin           Read base64 payload from stdin
  --api-port=N             Frame0 desktop HTTP API port (default: config or 58320)
  --query=TEXT             Search query
  --limit=N                Search limit (default 20)
  --dry-run                Skip writes; equivalent to \$SNAP_DRY_RUN=1
  -h, --help               Show this help
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --action=*)        ACTION="${1#--action=}" ;;
    --project-root=*)  PROJECT_ROOT="${1#--project-root=}" ;;
    --page-id=*)       PAGE_ID="${1#--page-id=}" ;;
    --parent-id=*)     PARENT_ID="${1#--parent-id=}" ;;
    --title=*)         TITLE="${1#--title=}" ;;
    --shapes=*)        SHAPES_JSON="${1#--shapes=}" ;;
    --shapes-file=*)   SHAPES_FILE="${1#--shapes-file=}" ;;
    --output-path=*)   OUTPUT_PATH="${1#--output-path=}" ;;
    --format=*)        EXPORT_FORMAT="${1#--format=}" ;;
    --scale=*)         EXPORT_SCALE="${1#--scale=}" ;;
    --base64-data=*)   BASE64_DATA="${1#--base64-data=}" ;;
    --base64-file=*)   BASE64_FILE="${1#--base64-file=}" ;;
    --base64-stdin)    BASE64_STDIN="true" ;;
    --api-port=*)      API_PORT="${1#--api-port=}" ;;
    --query=*)         QUERY="${1#--query=}" ;;
    --limit=*)         LIMIT="${1#--limit=}" ;;
    --dry-run)         DRY_RUN="true" ;;
    -h|--help)         usage; exit 0 ;;
    *) echo "ERROR: unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required" >&2; exit 2; }
[ -z "$ACTION" ] && { echo "ERROR: --action required" >&2; exit 2; }

case "$ACTION" in
  create-page|get-page|update-page|delete-page|list-pages|add-shapes|export-page|export-png|save-export) ;;
  *) echo "ERROR: invalid --action: $ACTION" >&2; exit 2 ;;
esac

# Internal defaults — helper context-agnostic, ne lit pas la config projet.
[ -z "$EXPORT_FORMAT" ] && EXPORT_FORMAT="png"
[ -z "$EXPORT_SCALE"  ] && EXPORT_SCALE="2"
[ -z "$API_PORT"      ] && API_PORT="58320"

# Format enum depends on action:
#   export-page (legacy MCP descriptor) keeps png/svg/pdf for backward compat
#   export-png (HTTP API) accepts png/jpeg/webp — Frame0's actual API surface
if [ "$ACTION" = "export-png" ]; then
  case "$EXPORT_FORMAT" in png|jpeg|webp) ;; *) echo "ERROR: bad --format for export-png: $EXPORT_FORMAT (allowed: png|jpeg|webp)" >&2; exit 2 ;; esac
else
  case "$EXPORT_FORMAT" in png|svg|pdf)   ;; *) echo "ERROR: bad --format: $EXPORT_FORMAT" >&2; exit 2 ;; esac
fi
case "$EXPORT_SCALE"  in 1|2|3) ;; *) echo "ERROR: bad --scale: $EXPORT_SCALE" >&2; exit 2 ;; esac
case "$API_PORT" in
  ''|*[!0-9]*) echo "ERROR: --api-port must be numeric: $API_PORT" >&2; exit 2 ;;
  *) [ "$API_PORT" -ge 1 ] && [ "$API_PORT" -le 65535 ] || { echo "ERROR: --api-port out of range: $API_PORT" >&2; exit 2; } ;;
esac

# --- per-action validation -----------------------------------------------
need() { [ -n "$1" ] || { echo "ERROR: $2" >&2; exit 2; }; }

case "$ACTION" in
  create-page)
    need "$TITLE" "--title required for create-page" ;;
  get-page|delete-page)
    need "$PAGE_ID" "--page-id required for $ACTION" ;;
  update-page)
    need "$PAGE_ID" "--page-id required for update-page"
    [ -n "$TITLE" ] || { echo "ERROR: update-page needs --title" >&2; exit 2; } ;;
  list-pages)
    need "$QUERY" "--query required for list-pages" ;;
  add-shapes)
    need "$PAGE_ID" "--page-id required for add-shapes"
    [ -n "$SHAPES_JSON" ] || [ -n "$SHAPES_FILE" ] \
      || { echo "ERROR: --shapes or --shapes-file required" >&2; exit 2; }
    [ -n "$SHAPES_JSON" ] && [ -n "$SHAPES_FILE" ] \
      && { echo "ERROR: pass either --shapes or --shapes-file, not both" >&2; exit 2; }
    if [ -n "$SHAPES_FILE" ]; then
      [ -f "$SHAPES_FILE" ] || { echo "ERROR: shapes-file not found: $SHAPES_FILE" >&2; exit 1; }
      SHAPES_JSON=$(cat "$SHAPES_FILE")
    fi
    echo "$SHAPES_JSON" | jq -e 'type == "array"' >/dev/null 2>&1 \
      || { echo "ERROR: --shapes must be a JSON array" >&2; exit 2; } ;;
  export-page)
    need "$PAGE_ID"     "--page-id required for export-page"
    need "$OUTPUT_PATH" "--output-path required for export-page" ;;
  export-png)
    need "$PAGE_ID"     "--page-id required for export-png"
    need "$OUTPUT_PATH" "--output-path required for export-png" ;;
  save-export)
    need "$OUTPUT_PATH" "--output-path required for save-export"
    # Exactly one base64 source.
    src_count=0
    [ -n "$BASE64_DATA" ]    && src_count=$((src_count + 1))
    [ -n "$BASE64_FILE" ]    && src_count=$((src_count + 1))
    [ "$BASE64_STDIN" = "true" ] && src_count=$((src_count + 1))
    [ "$src_count" -eq 0 ] && { echo "ERROR: save-export needs --base64-data, --base64-file, or --base64-stdin" >&2; exit 2; }
    [ "$src_count" -gt 1 ] && { echo "ERROR: --base64-data, --base64-file, --base64-stdin are mutually exclusive" >&2; exit 2; }
    if [ -n "$BASE64_FILE" ]; then
      [ -f "$BASE64_FILE" ] || { echo "ERROR: base64-file not found: $BASE64_FILE" >&2; exit 1; }
    fi ;;
esac

# --- export-png (local HTTP call, no MCP) --------------------------------
if [ "$ACTION" = "export-png" ]; then
  # Map --format to MIME type accepted by Frame0's file:export-image command.
  case "$EXPORT_FORMAT" in
    png)  MIME="image/png" ;;
    jpeg) MIME="image/jpeg" ;;
    webp) MIME="image/webp" ;;
  esac

  API_BASE="${SNAP_FRAME0_API_BASE:-http://localhost:${API_PORT}}"
  REQ_BODY=$(jq -nc --arg pid "$PAGE_ID" --arg fmt "$MIME" '
    {command:"file:export-image", args:{pageId:$pid, format:$fmt, fillBackground:true}}')

  if [ "$DRY_RUN" = "true" ]; then
    jq -nc --arg act "$ACTION" --arg pid "$PAGE_ID" --arg out "$OUTPUT_PATH" \
           --arg api "$API_BASE" --arg mime "$MIME" '
      {ok:true, mode:"dry-run", action:$act, platform:"frame0",
       result:{dry_run:true, page_id:$pid, output_path:$out, api_base:$api, mime:$mime, written:false}}'
    exit 0
  fi

  # Test stub: when SNAP_FRAME0_MOCK_RESPONSE_FILE is set, read the JSON body
  # from that file instead of making a real HTTP call. Production code paths
  # always hit the live API.
  if [ -n "${SNAP_FRAME0_MOCK_RESPONSE_FILE:-}" ]; then
    [ -f "$SNAP_FRAME0_MOCK_RESPONSE_FILE" ] || { echo "ERROR: mock response file not found: $SNAP_FRAME0_MOCK_RESPONSE_FILE" >&2; exit 1; }
    RESP=$(cat "$SNAP_FRAME0_MOCK_RESPONSE_FILE")
  else
    command -v curl >/dev/null 2>&1 || { echo "ERROR: curl required for export-png" >&2; exit 2; }
    RESP=$(curl -fsS -X POST "${API_BASE}/execute_command" \
      -H "Content-Type: application/json" \
      --data-binary "$REQ_BODY" 2>/dev/null) || {
        echo "ERROR: HTTP call to ${API_BASE}/execute_command failed (Frame0 desktop not running on port ${API_PORT}?)" >&2
        exit 1
      }
  fi

  # Validate JSON shape: {success:bool, data:string} or {success:false, error}.
  echo "$RESP" | jq -e 'type == "object" and has("success")' >/dev/null 2>&1 || {
    echo "ERROR: Frame0 API returned unexpected response (not a JSON object with .success)" >&2
    exit 1
  }
  SUCCESS=$(echo "$RESP" | jq -r '.success')
  if [ "$SUCCESS" != "true" ]; then
    ERR=$(echo "$RESP" | jq -r '.error // "(no error message)"')
    echo "ERROR: Frame0 API: ${ERR}" >&2
    exit 1
  fi
  PAYLOAD=$(echo "$RESP" | jq -r '.data // empty')
  [ -n "$PAYLOAD" ] || { echo "ERROR: Frame0 API returned success but no .data" >&2; exit 1; }
  # Strip data URI prefix if Frame0 ever wraps it.
  case "$PAYLOAD" in
    data:*\;base64,*) PAYLOAD="${PAYLOAD#*;base64,}" ;;
  esac
  PAYLOAD=$(printf '%s' "$PAYLOAD" | tr -d '[:space:]')

  TARGET_DIR=$(dirname "$OUTPUT_PATH")
  mkdir -p "$TARGET_DIR" || { echo "ERROR: cannot create target dir: $TARGET_DIR" >&2; exit 1; }
  if ! printf '%s' "$PAYLOAD" | base64 --decode > "$OUTPUT_PATH" 2>/dev/null; then
    echo "ERROR: base64 decode failed (target may be partial: $OUTPUT_PATH)" >&2
    exit 1
  fi
  [ -s "$OUTPUT_PATH" ] || { echo "ERROR: decoded file is empty: $OUTPUT_PATH" >&2; exit 1; }

  SIZE=$(wc -c < "$OUTPUT_PATH" | tr -d ' ')
  jq -nc --arg act "$ACTION" --arg out "$OUTPUT_PATH" --arg api "$API_BASE" \
         --arg mime "$MIME" --argjson sz "$SIZE" '
    {ok:true, mode:"local", action:$act, platform:"frame0",
     result:{output_path:$out, written:true, bytes:$sz, mime:$mime, api_base:$api}}'
  exit 0
fi

# --- save-export (local, no MCP) -----------------------------------------
if [ "$ACTION" = "save-export" ]; then
  # Gather payload.
  if [ -n "$BASE64_DATA" ]; then
    PAYLOAD="$BASE64_DATA"
  elif [ -n "$BASE64_FILE" ]; then
    PAYLOAD=$(cat "$BASE64_FILE")
  else
    PAYLOAD=$(cat)
  fi
  # Strip data URI prefix if present (e.g. "data:image/png;base64,...").
  case "$PAYLOAD" in
    data:*\;base64,*) PAYLOAD="${PAYLOAD#*;base64,}" ;;
  esac
  # Drop whitespace (newlines/spaces inside base64 strings).
  PAYLOAD=$(printf '%s' "$PAYLOAD" | tr -d '[:space:]')
  [ -n "$PAYLOAD" ] || { echo "ERROR: empty base64 payload" >&2; exit 1; }

  if [ "$DRY_RUN" = "true" ]; then
    BYTES=${#PAYLOAD}
    jq -nc --arg act "$ACTION" --arg out "$OUTPUT_PATH" --argjson b "$BYTES" '
      {ok:true, mode:"dry-run", action:$act, platform:"frame0",
       result:{dry_run:true, output_path:$out, written:false, base64_chars:$b}}'
    exit 0
  fi

  TARGET_DIR=$(dirname "$OUTPUT_PATH")
  mkdir -p "$TARGET_DIR" || { echo "ERROR: cannot create target dir: $TARGET_DIR" >&2; exit 1; }
  # `base64 --decode` works on both BSD (macOS 11+) and GNU coreutils.
  if ! printf '%s' "$PAYLOAD" | base64 --decode > "$OUTPUT_PATH" 2>/dev/null; then
    echo "ERROR: base64 decode failed (target may be partial: $OUTPUT_PATH)" >&2
    exit 1
  fi
  if [ ! -s "$OUTPUT_PATH" ]; then
    echo "ERROR: decoded file is empty: $OUTPUT_PATH" >&2
    exit 1
  fi
  SIZE=$(wc -c < "$OUTPUT_PATH" | tr -d ' ')
  jq -nc --arg act "$ACTION" --arg out "$OUTPUT_PATH" --argjson sz "$SIZE" '
    {ok:true, mode:"local", action:$act, platform:"frame0",
     result:{output_path:$out, written:true, bytes:$sz}}'
  exit 0
fi

# --- write detection / dry-run -------------------------------------------
is_write_action() {
  case "$1" in create-page|update-page|delete-page|add-shapes|export-page) return 0 ;; *) return 1 ;; esac
}

if [ "$DRY_RUN" = "true" ] && is_write_action "$ACTION"; then
  MOCK=$(jq -nc \
    --arg act "$ACTION" \
    --arg pid "${PAGE_ID:-DRY-PAGE-0}" \
    --arg parent "$PARENT_ID" \
    --arg title "$TITLE" \
    --arg out "$OUTPUT_PATH" \
    --arg fmt "$EXPORT_FORMAT" \
    --arg scl "$EXPORT_SCALE" '
    {dry_run:true, action:$act, page_id:$pid}
    | if $parent != "" then .parent_id   = $parent          else . end
    | if $title  != "" then .title       = $title           else . end
    | if $out    != "" then .output_path = $out             else . end
    | if $act == "export-page" then .format = $fmt | .scale = ($scl | tonumber) else . end')
  jq -nc --argjson r "$MOCK" --arg act "$ACTION" '
    {ok:true, mode:"dry-run", action:$act, platform:"frame0", result:$r}'
  exit 0
fi

# --- Build params object for descriptor ----------------------------------
PARAMS=$(jq -nc \
  --arg page    "$PAGE_ID" \
  --arg parent  "$PARENT_ID" \
  --arg title   "$TITLE" \
  --arg out     "$OUTPUT_PATH" \
  --arg query   "$QUERY" \
  --arg limit   "$LIMIT" \
  --arg fmt     "$EXPORT_FORMAT" \
  --arg scl     "$EXPORT_SCALE" \
  --argjson shapes "${SHAPES_JSON:-null}" \
  --arg act     "$ACTION" '
  {}
  | if $page   != "" then .page_id     = $page   else . end
  | if $parent != "" then .parent_id   = $parent else . end
  | if $title  != "" then .title       = $title  else . end
  | if $out    != "" then .output_path = $out    else . end
  | if $shapes != null then .shapes    = $shapes else . end
  | if $act == "list-pages" then .query = $query | .limit = ($limit | tonumber) else . end
  | if $act == "export-page" then .format = $fmt | .scale = ($scl | tonumber) else . end
')

DESCRIPTOR=$(jq -nc --arg act "$ACTION" --argjson p "$PARAMS" '
  {ok:false, mode:"mcp", reason:"mcp_required",
   descriptor: {platform:"frame0", action:$act, params:$p}}')

echo "$DESCRIPTOR"
exit 10
