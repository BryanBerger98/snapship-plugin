#!/usr/bin/env bash
# docs-adapter.sh — abstraction over AFFiNE / Notion docs.
#
# Actions: get | create | apply-template | upload-blob | update | search
#          | lookup-page | lookup-or-create-page | update-page-content
#          | set-page-tags | create-page-tree
#
# Both backends are MCP-only — there is no CLI equivalent. The adapter
# therefore emits a structured MCP descriptor on stdout and exits 10.
# The calling skill maps {platform, action} → concrete MCP tool name and
# performs the actual MCP call (subprocesses cannot invoke MCP directly).
#
# Dry-run write actions short-circuit with a mock success result.
# Read actions (get/search) ignore --dry-run and always emit a descriptor.
#
# Output JSON shapes:
#   mcp:  {"ok":false,"mode":"mcp","reason":"mcp_required","descriptor":{...}}  exit 10
#   dry:  {"ok":true,"mode":"dry-run","action":...,"platform":...,"result":{...}}  exit 0
#   err:  {"ok":false,"error":"..."}                                              exit 1|2
#
# Exit codes: 0=ok (dry-run), 1=runtime err, 2=bad args, 10=MCP descriptor

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SNAP_PROJECT_ROOT:-$(pwd)}"
ACTION=""
PLATFORM=""
PAGE_ID=""
PARENT_ID=""
WORKSPACE_ID=""
TITLE=""
CONTENT=""
CONTENT_FILE=""
TEMPLATE_NAME=""
TEMPLATE_VARS_JSON=""
BLOB_PATH=""
QUERY=""
LIMIT="20"
TAGS_JSON=""
PATH_TREE=""
DRY_RUN="${SNAP_DRY_RUN:-false}"

usage() {
  cat <<EOF
Usage: docs-adapter.sh --action=ACTION [OPTIONS]

Actions:
  get                    --page-id
  create                 --title  (--parent-id, --content[-file] optional)
  apply-template         --template-name --page-id|--parent-id (--template-vars JSON)
  upload-blob            --blob-path
  update                 --page-id (any of --title / --content[-file])
  search                 --query (--limit, default 20)
  lookup-page            --title (--parent-id|--workspace-id)
                         Find existing page by title under parent (idempotent helper).
  lookup-or-create-page  --title (--parent-id|--workspace-id, --content[-file] optional)
                         Lookup; create with content if missing.
  update-page-content    --page-id --content[-file]
                         Replace page body without touching title (used by /snap:doc-update).
  set-page-tags          --page-id --tags=JSON
                         JSON = array of tag strings. Replaces existing tags.
  create-page-tree       --path=A/B/C (--workspace-id|--parent-id root)
                         Idempotent — creates each segment as nested page if absent.
                         Returns leaf page id.

Options:
  --platform=affine|notion       Override config.documentation.platform
  --project-root=PATH            Project root (default: \$PWD)
  --page-id=ID                   Existing page identifier
  --parent-id=ID                 Parent page id (creates page underneath)
  --workspace-id=ID              Override config.documentation.workspace.id
  --title=TEXT
  --content=TEXT                 Markdown body (mutually exclusive with --content-file)
  --content-file=PATH            Read body from file
  --template-name=NAME           Bundled template key (e.g. prd_feature)
  --template-vars=JSON           JSON object of template substitutions
  --blob-path=PATH               File to upload (PNG, etc.)
  --query=TEXT                   Search query
  --limit=N                      Search result cap (default 20)
  --tags=JSON                    Tag list (JSON array of strings) for set-page-tags
  --path=A/B/C                   Slash-separated path for create-page-tree
  --dry-run                      Skip writes; equivalent to \$SNAP_DRY_RUN=1
  -h, --help                     Show this help
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --action=*)         ACTION="${1#--action=}" ;;
    --platform=*)       PLATFORM="${1#--platform=}" ;;
    --project-root=*)   PROJECT_ROOT="${1#--project-root=}" ;;
    --page-id=*)        PAGE_ID="${1#--page-id=}" ;;
    --parent-id=*)      PARENT_ID="${1#--parent-id=}" ;;
    --workspace-id=*)   WORKSPACE_ID="${1#--workspace-id=}" ;;
    --title=*)          TITLE="${1#--title=}" ;;
    --content=*)        CONTENT="${1#--content=}" ;;
    --content-file=*)   CONTENT_FILE="${1#--content-file=}" ;;
    --template-name=*)  TEMPLATE_NAME="${1#--template-name=}" ;;
    --template-vars=*)  TEMPLATE_VARS_JSON="${1#--template-vars=}" ;;
    --blob-path=*)      BLOB_PATH="${1#--blob-path=}" ;;
    --query=*)          QUERY="${1#--query=}" ;;
    --limit=*)          LIMIT="${1#--limit=}" ;;
    --tags=*)           TAGS_JSON="${1#--tags=}" ;;
    --path=*)           PATH_TREE="${1#--path=}" ;;
    --dry-run)          DRY_RUN="true" ;;
    -h|--help)          usage; exit 0 ;;
    *) echo "ERROR: unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required" >&2; exit 2; }
[ -z "$ACTION" ] && { echo "ERROR: --action required" >&2; exit 2; }

case "$ACTION" in
  get|create|apply-template|upload-blob|update|search) ;;
  lookup-page|lookup-or-create-page|update-page-content|set-page-tags|create-page-tree) ;;
  *) echo "ERROR: invalid --action: $ACTION" >&2; exit 2 ;;
esac

# Resolve platform + workspace from config when omitted.
if { [ -z "$PLATFORM" ] || [ -z "$WORKSPACE_ID" ]; } && [ -f "${PROJECT_ROOT}/snapship.config.json" ]; then
  if [ -x "${SCRIPT_DIR}/load-config.sh" ]; then
    CFG=$(bash "${SCRIPT_DIR}/load-config.sh" --project-root="$PROJECT_ROOT" --no-validate 2>/dev/null || echo '{}')
    [ -z "$PLATFORM" ]     && PLATFORM=$(echo "$CFG"     | jq -r '.documentation.platform // ""')
    [ -z "$WORKSPACE_ID" ] && WORKSPACE_ID=$(echo "$CFG" | jq -r '.documentation.workspace.id // ""')
  fi
fi

[ -z "$PLATFORM" ] && { echo "ERROR: --platform required (or set documentation.platform in config)" >&2; exit 2; }

case "$PLATFORM" in
  affine|notion) ;;
  *) echo "ERROR: unsupported platform: $PLATFORM" >&2; exit 2 ;;
esac

# --- per-action arg validation -------------------------------------------
need() { [ -n "$1" ] || { echo "ERROR: $2" >&2; exit 2; }; }

case "$ACTION" in
  get)            need "$PAGE_ID"       "--page-id required for get" ;;
  create)         need "$TITLE"         "--title required for create" ;;
  apply-template) need "$TEMPLATE_NAME" "--template-name required for apply-template"
                  [ -n "$PAGE_ID" ] || [ -n "$PARENT_ID" ] || \
                    { echo "ERROR: --page-id or --parent-id required for apply-template" >&2; exit 2; } ;;
  upload-blob)    need "$BLOB_PATH"     "--blob-path required for upload-blob"
                  [ -f "$BLOB_PATH" ]  || { echo "ERROR: blob not found: $BLOB_PATH" >&2; exit 1; } ;;
  update)         need "$PAGE_ID"       "--page-id required for update"
                  [ -n "$TITLE" ] || [ -n "$CONTENT" ] || [ -n "$CONTENT_FILE" ] || \
                    { echo "ERROR: update needs --title or --content[-file]" >&2; exit 2; } ;;
  search)         need "$QUERY"         "--query required for search" ;;
  lookup-page)    need "$TITLE"         "--title required for lookup-page"
                  [ -n "$PARENT_ID" ] || [ -n "$WORKSPACE_ID" ] || \
                    { echo "ERROR: --parent-id or --workspace-id required for lookup-page" >&2; exit 2; } ;;
  lookup-or-create-page)
                  need "$TITLE"         "--title required for lookup-or-create-page"
                  [ -n "$PARENT_ID" ] || [ -n "$WORKSPACE_ID" ] || \
                    { echo "ERROR: --parent-id or --workspace-id required for lookup-or-create-page" >&2; exit 2; } ;;
  update-page-content)
                  need "$PAGE_ID"       "--page-id required for update-page-content"
                  [ -n "$CONTENT" ] || [ -n "$CONTENT_FILE" ] || \
                    { echo "ERROR: update-page-content needs --content or --content-file" >&2; exit 2; } ;;
  set-page-tags)  need "$PAGE_ID"       "--page-id required for set-page-tags"
                  need "$TAGS_JSON"     "--tags=JSON required for set-page-tags"
                  echo "$TAGS_JSON" | jq -e 'type == "array" and (all(.[]; type == "string"))' >/dev/null 2>&1 \
                    || { echo "ERROR: --tags must be JSON array of strings" >&2; exit 2; } ;;
  create-page-tree)
                  need "$PATH_TREE"     "--path required for create-page-tree"
                  [[ "$PATH_TREE" == */* ]] || \
                    { echo "ERROR: --path must contain at least one '/' segment" >&2; exit 2; }
                  [ -n "$PARENT_ID" ] || [ -n "$WORKSPACE_ID" ] || \
                    { echo "ERROR: --parent-id or --workspace-id required for create-page-tree" >&2; exit 2; } ;;
esac

# Validate template-vars JSON if provided
if [ -n "$TEMPLATE_VARS_JSON" ]; then
  echo "$TEMPLATE_VARS_JSON" | jq empty 2>/dev/null \
    || { echo "ERROR: --template-vars must be valid JSON" >&2; exit 2; }
fi

# Resolve content from file if requested
if [ -n "$CONTENT_FILE" ]; then
  [ -f "$CONTENT_FILE" ] || { echo "ERROR: content-file not found: $CONTENT_FILE" >&2; exit 1; }
  [ -n "$CONTENT" ] && { echo "ERROR: pass either --content or --content-file, not both" >&2; exit 2; }
  CONTENT=$(cat "$CONTENT_FILE")
fi

# --- helpers --------------------------------------------------------------
ok_dry() {
  local result_json="$1"
  jq -nc --arg act "$ACTION" --arg plat "$PLATFORM" --argjson r "$result_json" '
    {ok:true, mode:"dry-run", action:$act, platform:$plat, result:$r}'
}

# --- DRY RUN write shortcut ----------------------------------------------
is_write_action() {
  case "$1" in
    create|apply-template|upload-blob|update) return 0 ;;
    lookup-or-create-page|update-page-content|set-page-tags|create-page-tree) return 0 ;;
    *) return 1 ;;
  esac
}

if [ "$DRY_RUN" = "true" ] && is_write_action "$ACTION"; then
  MOCK=$(jq -nc \
    --arg act "$ACTION" \
    --arg pid "${PAGE_ID:-DRY-PAGE-0}" \
    --arg parent "${PARENT_ID}" \
    --arg title "${TITLE}" \
    --arg tpl "${TEMPLATE_NAME}" \
    --arg blob "${BLOB_PATH}" \
    --arg ws "${WORKSPACE_ID}" \
    --arg ptree "${PATH_TREE}" \
    --argjson tags "${TAGS_JSON:-null}" '
    {dry_run:true, action:$act, page_id:$pid}
    | if $parent != "" then .parent_id = $parent else . end
    | if $title  != "" then .title     = $title  else . end
    | if $tpl    != "" then .template  = $tpl    else . end
    | if $blob   != "" then .blob_path = $blob   else . end
    | if $ws     != "" then .workspace = $ws     else . end
    | if $ptree  != "" then .path      = $ptree  else . end
    | if $tags  != null then .tags     = $tags   else . end')
  ok_dry "$MOCK"
  exit 0
fi

# --- Build params object --------------------------------------------------
PARAMS=$(jq -nc \
  --arg page    "$PAGE_ID" \
  --arg parent  "$PARENT_ID" \
  --arg ws      "$WORKSPACE_ID" \
  --arg title   "$TITLE" \
  --arg content "$CONTENT" \
  --arg tpl     "$TEMPLATE_NAME" \
  --arg blob    "$BLOB_PATH" \
  --arg query   "$QUERY" \
  --arg limit   "$LIMIT" \
  --arg ptree   "$PATH_TREE" \
  --argjson tvars "${TEMPLATE_VARS_JSON:-null}" \
  --argjson tags  "${TAGS_JSON:-null}" '
  {}
  | if $page    != "" then .page_id       = $page                else . end
  | if $parent  != "" then .parent_id     = $parent              else . end
  | if $ws      != "" then .workspace_id  = $ws                  else . end
  | if $title   != "" then .title         = $title               else . end
  | if $content != "" then .content       = $content             else . end
  | if $tpl     != "" then .template_name = $tpl                 else . end
  | if $blob    != "" then .blob_path     = $blob                else . end
  | if $query   != "" then .query         = $query               else . end
  | if $ptree   != "" then .path          = $ptree               else . end
  | if $tvars   != null then .template_vars = $tvars             else . end
  | if $tags    != null then .tags          = $tags              else . end
  | (if . | has("query") then .limit = ($limit | tonumber) else . end)
')

# --- Emit MCP descriptor --------------------------------------------------
DESCRIPTOR=$(jq -nc --arg plat "$PLATFORM" --arg act "$ACTION" --argjson p "$PARAMS" '
  {ok:false, mode:"mcp", reason:"mcp_required",
   descriptor: {platform:$plat, action:$act, params:$p}}')

echo "$DESCRIPTOR"
exit 10
