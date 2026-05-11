#!/usr/bin/env bash
# penpot-helper.sh — wrapper for batch operations on the Penpot MCP server.
#
# Penpot MCP exposes three high-level tools (`get_overview`, `query_docs`,
# `execute_code`) plus an asset export tool. Most write operations route
# through `execute_code` with a JS snippet that runs inside Penpot's plugin
# context (globals: penpot, penpotUtils, storage, console). Asset export
# routes to the `export_shape` tool, which accepts an absolute `filePath`
# and writes the PNG/SVG to disk directly — no HTTP bypass needed.
#
# Like frame0-helper.sh, this helper emits MCP descriptors on stdout (exit 10)
# for the calling skill to dispatch. The descriptor names the underlying
# Penpot MCP tool (`execute_code` or `export_shape`) and packs the params.
#
# Actions:
#   create-page    --title (--parent-id ignored — Penpot pages are file-scoped)
#                  → tool=execute_code, JS: const p = penpot.createPage(); p.name = ...
#   get-page       --page-id
#                  → tool=execute_code, JS: returns penpotUtils.getPageById(...)
#   update-page    --page-id (--title)
#                  → tool=execute_code, JS: rename page
#   delete-page    --page-id
#                  → tool=execute_code, JS: penpot.removePage(page)
#   list-pages     --query (--limit, default 20)
#                  → tool=execute_code, JS: returns penpotUtils.getPages() filtered
#   add-shapes     --page-id --shapes (JSON array)
#                  → tool=execute_code, JS: iterates and calls penpot.createRectangle/
#                    createText/createEllipse based on shape.type. Each shape:
#                    { "type":"rect|text|ellipse", "name":"...", "x":N, "y":N,
#                      "width":N, "height":N, "fill":"#hex", "text":"..." }
#   export-png     --page-id|--shape-id --output-path (--format png|svg)
#                  → tool=export_shape, params {shapeId, format, filePath:absolute}.
#                    Penpot writes the asset directly; nothing to decode locally.
#                    --output-path must be absolute (Penpot rejects relative paths).
#   get-current-file
#                  → tool=execute_code, JS returns {id, name} of penpot.currentFile.
#                    Used by skill preflight to verify the user has the correct
#                    file open in their Penpot browser tab (no programmatic
#                    "openFile" API exists; the binding is the tab + plugin
#                    connection).
#
# Defaults for export_format read from config.wireframes.export_format.
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
SHAPE_ID=""
PARENT_ID=""
TITLE=""
SHAPES_JSON=""
SHAPES_FILE=""
OUTPUT_PATH=""
EXPORT_FORMAT=""
QUERY=""
LIMIT="20"
DRY_RUN="${SNAP_DRY_RUN:-false}"

usage() {
  cat <<EOF
Usage: penpot-helper.sh --action=ACTION [OPTIONS]

Actions:
  create-page       --title
  get-page          --page-id
  update-page       --page-id (--title)
  delete-page       --page-id
  list-pages        --query (--limit, default 20)
  add-shapes        --page-id --shapes JSON|@file
  export-png        (--page-id|--shape-id) --output-path (--format png|svg)
  get-current-file  (no args — returns {id, name} of penpot.currentFile)

Options:
  --project-root=PATH      Project root (default: \$PWD)
  --page-id=ID             Penpot page UUID (or "current" for active page)
  --shape-id=ID            Penpot shape UUID (or "selection" for active selection)
  --title=TEXT
  --shapes=JSON            JSON array of shape descriptors
  --shapes-file=PATH       Read shapes JSON from file
  --output-path=PATH       Absolute path for exported asset (Penpot constraint)
  --format=png|svg         Export format (config default: png)
  --query=TEXT             Search query (case-insensitive substring on page name)
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
    --shape-id=*)      SHAPE_ID="${1#--shape-id=}" ;;
    --parent-id=*)     PARENT_ID="${1#--parent-id=}" ;;
    --title=*)         TITLE="${1#--title=}" ;;
    --shapes=*)        SHAPES_JSON="${1#--shapes=}" ;;
    --shapes-file=*)   SHAPES_FILE="${1#--shapes-file=}" ;;
    --output-path=*)   OUTPUT_PATH="${1#--output-path=}" ;;
    --format=*)        EXPORT_FORMAT="${1#--format=}" ;;
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
  create-page|get-page|update-page|delete-page|list-pages|add-shapes|export-png|get-current-file) ;;
  *) echo "ERROR: invalid --action: $ACTION" >&2; exit 2 ;;
esac

# Read config defaults.
CFG_FORMAT=""
if [ -f "${PROJECT_ROOT}/snapship.config.json" ] && [ -x "${SCRIPT_DIR}/load-config.sh" ]; then
  CFG=$(bash "${SCRIPT_DIR}/load-config.sh" --project-root="$PROJECT_ROOT" --no-validate 2>/dev/null || echo '{}')
  CFG_FORMAT=$(echo "$CFG" | jq -r '.wireframes.export_format // ""')
fi
[ -z "$EXPORT_FORMAT" ] && EXPORT_FORMAT="${CFG_FORMAT:-png}"

# Penpot export_shape supports png/svg only.
if [ "$ACTION" = "export-png" ]; then
  case "$EXPORT_FORMAT" in png|svg) ;; *) echo "ERROR: bad --format for export-png: $EXPORT_FORMAT (allowed: png|svg)" >&2; exit 2 ;; esac
fi

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
  export-png)
    # Penpot's export_shape needs a shape target. Accept either --shape-id
    # (explicit) or --page-id (will resolve to page root shape in JS at runtime).
    [ -n "$SHAPE_ID" ] || [ -n "$PAGE_ID" ] \
      || { echo "ERROR: export-png needs --shape-id or --page-id" >&2; exit 2; }
    need "$OUTPUT_PATH" "--output-path required for export-png"
    case "$OUTPUT_PATH" in
      /*) ;;
      *) echo "ERROR: --output-path must be absolute for Penpot export (got: $OUTPUT_PATH)" >&2; exit 2 ;;
    esac ;;
esac

# --- write detection / dry-run -------------------------------------------
is_write_action() {
  case "$1" in create-page|update-page|delete-page|add-shapes|export-png) return 0 ;; *) return 1 ;; esac
}

if [ "$DRY_RUN" = "true" ] && is_write_action "$ACTION"; then
  MOCK=$(jq -nc \
    --arg act "$ACTION" \
    --arg pid "${PAGE_ID:-DRY-PAGE-0}" \
    --arg sid "${SHAPE_ID:-DRY-SHAPE-0}" \
    --arg title "$TITLE" \
    --arg out "$OUTPUT_PATH" \
    --arg fmt "$EXPORT_FORMAT" '
    {dry_run:true, action:$act}
    | if $act == "export-png" then .shape_id = $sid | .output_path = $out | .format = $fmt | .written = false
      else .page_id = $pid end
    | if $title != "" then .title = $title else . end')
  jq -nc --argjson r "$MOCK" --arg act "$ACTION" '
    {ok:true, mode:"dry-run", action:$act, platform:"penpot", result:$r}'
  exit 0
fi

# --- Build MCP descriptor ------------------------------------------------
#
# Each action maps to a Penpot MCP tool call. Two tools cover everything:
#   - execute_code: arbitrary JS in plugin context (CRUD + queries)
#   - export_shape: writes PNG/SVG to absolute filePath
#
# JS bodies are built here so the dispatcher just forwards {tool, args}
# to the MCP server without further templating.

build_js() {
  case "$ACTION" in
    create-page)
      jq -nc --arg title "$TITLE" '
        "const p = penpot.createPage(); p.name = " + ($title | tojson) + "; ({id: p.id, name: p.name});"' ;;
    get-page)
      jq -nc --arg pid "$PAGE_ID" '
        "const p = penpotUtils.getPageById(" + ($pid | tojson) + "); p ? ({id: p.id, name: p.name}) : null;"' ;;
    update-page)
      jq -nc --arg pid "$PAGE_ID" --arg title "$TITLE" '
        "const p = penpotUtils.getPageById(" + ($pid | tojson) + "); if (!p) throw new Error(\"page not found\"); p.name = " + ($title | tojson) + "; ({id: p.id, name: p.name});"' ;;
    delete-page)
      jq -nc --arg pid "$PAGE_ID" '
        "const p = penpotUtils.getPageById(" + ($pid | tojson) + "); if (!p) throw new Error(\"page not found\"); penpot.removePage(p); ({id: " + ($pid | tojson) + ", removed: true});"' ;;
    list-pages)
      jq -nc --arg q "$QUERY" --arg lim "$LIMIT" '
        "const q = " + ($q | tojson) + ".toLowerCase(); penpotUtils.getPages().filter(p => p.name.toLowerCase().includes(q)).slice(0, " + $lim + ").map(p => ({id: p.id, name: p.name}));"' ;;
    get-current-file)
      jq -nc '
        "const f = penpot.currentFile; f ? ({id: f.id, name: f.name}) : null;"' ;;
    add-shapes)
      # Compact shapes JSON for embedding in JS string.
      local shapes_compact
      shapes_compact=$(echo "$SHAPES_JSON" | jq -c '.')
      jq -nc --arg pid "$PAGE_ID" --arg shapes "$shapes_compact" '
        "const page = penpotUtils.getPageById(" + ($pid | tojson) + "); if (!page) throw new Error(\"page not found\"); penpot.openPage(page); const shapes = " + $shapes + "; const created = shapes.map(s => { let shape; if (s.type === \"text\") { shape = penpot.createText(s.text || \"\"); } else if (s.type === \"ellipse\") { shape = penpot.createEllipse(); } else { shape = penpot.createRectangle(); } if (s.name) shape.name = s.name; if (typeof s.x === \"number\") shape.x = s.x; if (typeof s.y === \"number\") shape.y = s.y; if (typeof s.width === \"number\") shape.resize(s.width, shape.height || s.height || 0); if (typeof s.height === \"number\") shape.resize(shape.width || s.width || 0, s.height); if (s.fill) shape.fills = [{fillColor: s.fill, fillOpacity: 1}]; return {id: shape.id, name: shape.name, type: s.type}; }); ({page_id: page.id, created});"' ;;
  esac
}

if [ "$ACTION" = "export-png" ]; then
  # export_shape tool — Penpot writes the file itself. "selection" is the
  # special id for the active selection if neither shape-id nor page-id resolves.
  SHAPE_TARGET="${SHAPE_ID:-$PAGE_ID}"
  PARAMS=$(jq -nc \
    --arg sid "$SHAPE_TARGET" \
    --arg fmt "$EXPORT_FORMAT" \
    --arg out "$OUTPUT_PATH" '
    {shapeId:$sid, format:$fmt, filePath:$out}')
  DESCRIPTOR=$(jq -nc --arg act "$ACTION" --argjson p "$PARAMS" '
    {ok:false, mode:"mcp", reason:"mcp_required",
     descriptor: {platform:"penpot", action:$act, tool:"export_shape", params:$p}}')
  echo "$DESCRIPTOR"
  exit 10
fi

# All other actions route through execute_code.
JS_CODE=$(build_js)
PARAMS=$(jq -nc --argjson code "$JS_CODE" '{code:$code}')
DESCRIPTOR=$(jq -nc --arg act "$ACTION" --argjson p "$PARAMS" '
  {ok:false, mode:"mcp", reason:"mcp_required",
   descriptor: {platform:"penpot", action:$act, tool:"execute_code", params:$p}}')

echo "$DESCRIPTOR"
exit 10
