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
#
# Defaults for export_format / export_scale read from
# config.wireframes.{export_format,export_scale} when not specified.
#
# Output JSON shapes:
#   mcp:  {"ok":false,"mode":"mcp","reason":"mcp_required","descriptor":{...}}  exit 10
#   dry:  {"ok":true,"mode":"dry-run","action":...,"result":{...}}              exit 0
#   err:  {"ok":false,"error":"..."}                                            exit 1|2

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${ARTYSAN_PROJECT_ROOT:-$(pwd)}"
ACTION=""
PAGE_ID=""
PARENT_ID=""
TITLE=""
SHAPES_JSON=""
SHAPES_FILE=""
OUTPUT_PATH=""
EXPORT_FORMAT=""
EXPORT_SCALE=""
QUERY=""
LIMIT="20"
DRY_RUN="${ARTYSAN_DRY_RUN:-false}"

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
  export-page    --page-id --output-path (--format, --scale)

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
  --query=TEXT             Search query
  --limit=N                Search limit (default 20)
  --dry-run                Skip writes; equivalent to \$ARTYSAN_DRY_RUN=1
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
  create-page|get-page|update-page|delete-page|list-pages|add-shapes|export-page) ;;
  *) echo "ERROR: invalid --action: $ACTION" >&2; exit 2 ;;
esac

# Read config defaults for export.
CFG_FORMAT=""
CFG_SCALE=""
if [ -f "${PROJECT_ROOT}/artysan.config.json" ] && [ -x "${SCRIPT_DIR}/load-config.sh" ]; then
  CFG=$(bash "${SCRIPT_DIR}/load-config.sh" --project-root="$PROJECT_ROOT" --no-validate 2>/dev/null || echo '{}')
  CFG_FORMAT=$(echo "$CFG" | jq -r '.wireframes.export_format // ""')
  CFG_SCALE=$(echo  "$CFG" | jq -r '.wireframes.export_scale  // ""')
fi
[ -z "$EXPORT_FORMAT" ] && EXPORT_FORMAT="${CFG_FORMAT:-png}"
[ -z "$EXPORT_SCALE"  ] && EXPORT_SCALE="${CFG_SCALE:-2}"

case "$EXPORT_FORMAT" in png|svg|pdf) ;; *) echo "ERROR: bad --format: $EXPORT_FORMAT" >&2; exit 2 ;; esac
case "$EXPORT_SCALE"  in 1|2|3)        ;; *) echo "ERROR: bad --scale: $EXPORT_SCALE"  >&2; exit 2 ;; esac

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
esac

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
