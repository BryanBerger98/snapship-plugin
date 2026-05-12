#!/usr/bin/env bash
# figma-helper.sh — wrapper pour opérations batch sur le serveur figma-console-mcp.
#
# figma-console-mcp expose ~100 outils, mais le CRUD plugin-API passe par
# `figma_execute` (JS Plugin API brut, retour JSON). Les exports passent aussi
# par `figma_execute` en injectant `node.exportAsync()` — la réponse MCP renvoie
# les octets encodés base64 inline, le skill appelant décode et écrit sur disque
# via `figma-helper.sh save-export`.
#
# Helper context-agnostic depuis v0.5: ne lit aucune configuration projet.
# Les params (--file-key, --format, --scale) sont passés explicitement par le
# skill. Défauts internes: format=png, scale=2.
#
# Actions (miroir surface penpot-helper):
#   create-page    --title
#                  → tool=figma_execute, JS: figma.createPage()
#   get-page       --page-id
#                  → tool=figma_execute, JS: figma.getNodeById(id) puis check type=PAGE
#   update-page    --page-id --title
#                  → tool=figma_execute, JS: rename page node
#   delete-page    --page-id
#                  → tool=figma_execute, JS: page.remove()
#   list-pages     --query (--limit, défaut 20)
#                  → tool=figma_execute, JS: figma.root.children filtré par nom
#   add-shapes     --page-id --shapes JSON|--shapes-file
#                  shapes: [{type:"rect|text|ellipse", name, x, y, width, height, fill:"#hex", text}]
#                  → tool=figma_execute, JS: switch currentPage puis createRectangle/Text/Ellipse.
#                    Couleurs converties #hex → {r,g,b} 0-1 côté JS. Texte requiert
#                    loadFontAsync(Inter Regular) avant set characters.
#                    Limite batch: 100 shapes/appel (contrainte MCP).
#   export-png     (--page-id|--shape-id) --output-path (--format png|svg|jpg|pdf, --scale 1..4)
#                  → tool=figma_execute, JS: await node.exportAsync({format, constraint}).
#                    Retourne base64 via figma.base64Encode(bytes). Le skill décode
#                    et écrit sur disque (helper emet juste descripteur + result_path).
#   get-current-file
#                  → tool=figma_execute, JS: ({id: figma.fileKey, name: figma.root.name})
#                    Préflight skill: vérifie que Figma Desktop a le bon fichier ouvert.
#   save-export    --output-path --base64-data DATA|--base64-file PATH|--base64-stdin
#                  Décode payload base64 (retour figma_execute) et écrit fichier.
#                  Local-only — pas de descripteur MCP. Strip prefix data:image/...;base64,.
#
# Format données Figma:
#   - Couleurs: {r, g, b} plages 0-1 (pas 0-255). Helper convertit #hex.
#   - Exports: Uint8Array → base64 via figma.base64Encode() côté plugin.
#   - Batch: 100 items max/appel figma_execute.
#
# Output JSON shapes:
#   mcp:  {"ok":false,"mode":"mcp","reason":"mcp_required","descriptor":{...}}  exit 10
#   dry:  {"ok":true,"mode":"dry-run","action":...,"result":{...}}              exit 0
#   ok:   {"ok":true,"mode":"local","action":"save-export","result":{...}}      exit 0
#   err:  {"ok":false,"error":"..."}                                            exit 1|2

set -euo pipefail

ACTION=""
FILE_KEY=""
PAGE_ID=""
SHAPE_ID=""
TITLE=""
SHAPES_JSON=""
SHAPES_FILE=""
OUTPUT_PATH=""
EXPORT_FORMAT=""
EXPORT_SCALE=""
BASE64_DATA=""
BASE64_FILE=""
BASE64_STDIN="false"
QUERY=""
LIMIT="20"
DRY_RUN="${SNAP_DRY_RUN:-false}"

usage() {
  cat <<EOF
Usage: figma-helper.sh --action=ACTION [OPTIONS]

Actions:
  create-page       --title
  get-page          --page-id
  update-page       --page-id --title
  delete-page       --page-id
  list-pages        --query (--limit, défaut 20)
  add-shapes        --page-id --shapes JSON|@file
  export-png        (--page-id|--shape-id) --output-path (--format, --scale)
  get-current-file  (no args)
  save-export       --output-path --base64-data DATA|--base64-file PATH|--base64-stdin

Options:
  --file-key=KEY              Figma file key (métadonnée descripteur, non requis runtime)
  --page-id=ID                Figma page node ID
  --shape-id=ID               Figma shape node ID
  --title=TEXT
  --shapes=JSON               Tableau JSON shape descriptors
  --shapes-file=PATH          Lit shapes JSON depuis fichier
  --output-path=PATH          Chemin asset exporté (skill écrit)
  --format=png|svg|jpg|pdf    Format export (défaut interne: png)
  --scale=1|2|3|4             Échelle export (défaut interne: 2)
  --base64-data=DATA          Payload base64 (retour figma_execute)
  --base64-file=PATH          Lit base64 depuis fichier
  --base64-stdin              Lit base64 depuis stdin
  --query=TEXT                Requête recherche (sous-chaîne case-insensitive sur nom page)
  --limit=N                   Limite recherche (défaut 20)
  --dry-run                   Skip writes; équiv. \$SNAP_DRY_RUN=1
  -h, --help                  Affiche cette aide
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --action=*)        ACTION="${1#--action=}" ;;
    --file-key=*)      FILE_KEY="${1#--file-key=}" ;;
    --page-id=*)       PAGE_ID="${1#--page-id=}" ;;
    --shape-id=*)      SHAPE_ID="${1#--shape-id=}" ;;
    --title=*)         TITLE="${1#--title=}" ;;
    --shapes=*)        SHAPES_JSON="${1#--shapes=}" ;;
    --shapes-file=*)   SHAPES_FILE="${1#--shapes-file=}" ;;
    --output-path=*)   OUTPUT_PATH="${1#--output-path=}" ;;
    --format=*)        EXPORT_FORMAT="${1#--format=}" ;;
    --scale=*)         EXPORT_SCALE="${1#--scale=}" ;;
    --base64-data=*)   BASE64_DATA="${1#--base64-data=}" ;;
    --base64-file=*)   BASE64_FILE="${1#--base64-file=}" ;;
    --base64-stdin)    BASE64_STDIN="true" ;;
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
  create-page|get-page|update-page|delete-page|list-pages|add-shapes|export-png|get-current-file|save-export) ;;
  *) echo "ERROR: invalid --action: $ACTION" >&2; exit 2 ;;
esac

# Defaults internes — pas de lecture config.
[ -z "$EXPORT_FORMAT" ] && EXPORT_FORMAT="png"
[ -z "$EXPORT_SCALE"  ] && EXPORT_SCALE="2"

if [ "$ACTION" = "export-png" ]; then
  case "$EXPORT_FORMAT" in png|svg|jpg|pdf) ;; *) echo "ERROR: bad --format for export-png: $EXPORT_FORMAT (allowed: png|svg|jpg|pdf)" >&2; exit 2 ;; esac
  case "$EXPORT_SCALE" in 1|2|3|4) ;; *) echo "ERROR: bad --scale: $EXPORT_SCALE (allowed: 1|2|3|4)" >&2; exit 2 ;; esac
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
      || { echo "ERROR: --shapes must be a JSON array" >&2; exit 2; }
    SHAPES_COUNT=$(echo "$SHAPES_JSON" | jq 'length')
    [ "$SHAPES_COUNT" -le 100 ] \
      || { echo "ERROR: figma_execute batch limit is 100 shapes/call (got $SHAPES_COUNT)" >&2; exit 2; } ;;
  export-png)
    [ -n "$SHAPE_ID" ] || [ -n "$PAGE_ID" ] \
      || { echo "ERROR: export-png needs --shape-id or --page-id" >&2; exit 2; }
    need "$OUTPUT_PATH" "--output-path required for export-png" ;;
  save-export)
    need "$OUTPUT_PATH" "--output-path required for save-export"
    src_count=0
    [ -n "$BASE64_DATA" ]        && src_count=$((src_count + 1))
    [ -n "$BASE64_FILE" ]        && src_count=$((src_count + 1))
    [ "$BASE64_STDIN" = "true" ] && src_count=$((src_count + 1))
    [ "$src_count" -eq 0 ] && { echo "ERROR: save-export needs --base64-data, --base64-file, or --base64-stdin" >&2; exit 2; }
    [ "$src_count" -gt 1 ] && { echo "ERROR: --base64-data, --base64-file, --base64-stdin are mutually exclusive" >&2; exit 2; }
    if [ -n "$BASE64_FILE" ]; then
      [ -f "$BASE64_FILE" ] || { echo "ERROR: base64-file not found: $BASE64_FILE" >&2; exit 1; }
    fi ;;
esac

# --- save-export (local, no MCP) -----------------------------------------
if [ "$ACTION" = "save-export" ]; then
  if [ -n "$BASE64_DATA" ]; then
    PAYLOAD="$BASE64_DATA"
  elif [ -n "$BASE64_FILE" ]; then
    PAYLOAD=$(cat "$BASE64_FILE")
  else
    PAYLOAD=$(cat)
  fi
  [ -n "$PAYLOAD" ] || { echo "ERROR: empty base64 payload" >&2; exit 1; }
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
  jq -nc --arg out "$OUTPUT_PATH" --argjson sz "$SIZE" '
    {ok:true, mode:"local", action:"save-export", platform:"figma",
     result:{output_path:$out, written:true, bytes:$sz}}'
  exit 0
fi

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
    --arg fmt "$EXPORT_FORMAT" \
    --arg scl "$EXPORT_SCALE" '
    {dry_run:true, action:$act}
    | if $act == "export-png" then
        .shape_id = $sid | .page_id = $pid | .output_path = $out | .format = $fmt | .scale = ($scl|tonumber) | .written = false
      else .page_id = $pid end
    | if $title != "" then .title = $title else . end')
  jq -nc --argjson r "$MOCK" --arg act "$ACTION" '
    {ok:true, mode:"dry-run", action:$act, platform:"figma", result:$r}'
  exit 0
fi

# --- Build MCP descriptor (figma_execute) --------------------------------
#
# All actions route through `figma_execute` (single MCP tool). JS bodies are
# constructed here so the dispatcher just forwards {tool, args} to the MCP.
#
# Figma Plugin API notes:
#   - figma.createPage() auto-appends to figma.root
#   - figma.getNodeById(id) returns BaseNode|null; we check .type === "PAGE"
#   - text needs await figma.loadFontAsync({family:"Inter", style:"Regular"})
#   - colors: {r,g,b} 0-1; helper converts #RRGGBB → {r:R/255, g:G/255, b:B/255}
#   - exports: node.exportAsync({format,constraint}) → Uint8Array → figma.base64Encode()

build_js() {
  case "$ACTION" in
    create-page)
      jq -nc --arg title "$TITLE" '
        "const p = figma.createPage(); p.name = " + ($title | tojson) + "; ({id: p.id, name: p.name});"' ;;
    get-page)
      jq -nc --arg pid "$PAGE_ID" '
        "const n = figma.getNodeById(" + ($pid | tojson) + "); n && n.type === \"PAGE\" ? ({id: n.id, name: n.name}) : null;"' ;;
    update-page)
      jq -nc --arg pid "$PAGE_ID" --arg title "$TITLE" '
        "const n = figma.getNodeById(" + ($pid | tojson) + "); if (!n || n.type !== \"PAGE\") throw new Error(\"page not found\"); n.name = " + ($title | tojson) + "; ({id: n.id, name: n.name});"' ;;
    delete-page)
      jq -nc --arg pid "$PAGE_ID" '
        "const n = figma.getNodeById(" + ($pid | tojson) + "); if (!n || n.type !== \"PAGE\") throw new Error(\"page not found\"); n.remove(); ({id: " + ($pid | tojson) + ", removed: true});"' ;;
    list-pages)
      jq -nc --arg q "$QUERY" --arg lim "$LIMIT" '
        "const q = " + ($q | tojson) + ".toLowerCase(); figma.root.children.filter(p => p.name.toLowerCase().includes(q)).slice(0, " + $lim + ").map(p => ({id: p.id, name: p.name}));"' ;;
    get-current-file)
      jq -nc '
        "({id: figma.fileKey, name: figma.root.name});"' ;;
    add-shapes)
      local shapes_compact
      shapes_compact=$(echo "$SHAPES_JSON" | jq -c '.')
      jq -nc --arg pid "$PAGE_ID" --arg shapes "$shapes_compact" '
        "const page = figma.getNodeById(" + ($pid | tojson) + "); if (!page || page.type !== \"PAGE\") throw new Error(\"page not found\"); figma.currentPage = page; const shapes = " + $shapes + "; const hexToRgb = (h) => { const m = /^#?([a-f0-9]{6})$/i.exec(h || \"\"); if (!m) return null; const n = parseInt(m[1], 16); return {r:((n>>16)&255)/255, g:((n>>8)&255)/255, b:(n&255)/255}; }; const created = []; for (const s of shapes) { let shape; if (s.type === \"text\") { await figma.loadFontAsync({family:\"Inter\", style:\"Regular\"}); shape = figma.createText(); if (s.text) shape.characters = s.text; } else if (s.type === \"ellipse\") { shape = figma.createEllipse(); } else { shape = figma.createRectangle(); } if (s.name) shape.name = s.name; if (typeof s.x === \"number\") shape.x = s.x; if (typeof s.y === \"number\") shape.y = s.y; if (typeof s.width === \"number\" && typeof s.height === \"number\" && shape.resize) shape.resize(s.width, s.height); const rgb = hexToRgb(s.fill); if (rgb) shape.fills = [{type:\"SOLID\", color: rgb}]; page.appendChild(shape); created.push({id: shape.id, name: shape.name, type: s.type}); } ({page_id: page.id, created});"' ;;
    export-png)
      local target
      target="${SHAPE_ID:-$PAGE_ID}"
      local fmt_upper
      case "$EXPORT_FORMAT" in
        png)  fmt_upper="PNG" ;;
        svg)  fmt_upper="SVG" ;;
        jpg)  fmt_upper="JPG" ;;
        pdf)  fmt_upper="PDF" ;;
      esac
      jq -nc --arg nid "$target" --arg fmt "$fmt_upper" --arg scl "$EXPORT_SCALE" '
        "const n = figma.getNodeById(" + ($nid | tojson) + "); if (!n) throw new Error(\"node not found\"); const bytes = await n.exportAsync({format:\"" + $fmt + "\", constraint:{type:\"SCALE\", value:" + $scl + "}}); ({node_id: n.id, format:\"" + $fmt + "\", data: figma.base64Encode(bytes)});"' ;;
  esac
}

JS_CODE=$(build_js)
PARAMS=$(jq -nc --argjson code "$JS_CODE" '{code:$code}')

# For export-png, include result_path hint so the dispatcher knows where to
# write after decoding the base64 returned by figma_execute.
if [ "$ACTION" = "export-png" ]; then
  DESCRIPTOR=$(jq -nc --arg act "$ACTION" --argjson p "$PARAMS" \
                     --arg out "$OUTPUT_PATH" --arg fmt "$EXPORT_FORMAT" --arg scl "$EXPORT_SCALE" \
                     --arg fk "$FILE_KEY" '
    {ok:false, mode:"mcp", reason:"mcp_required",
     descriptor: {platform:"figma", action:$act, tool:"figma_execute", params:$p,
                  result_path:$out, format:$fmt, scale:($scl|tonumber),
                  file_key: (if $fk == "" then null else $fk end)}}')
else
  DESCRIPTOR=$(jq -nc --arg act "$ACTION" --argjson p "$PARAMS" --arg fk "$FILE_KEY" '
    {ok:false, mode:"mcp", reason:"mcp_required",
     descriptor: {platform:"figma", action:$act, tool:"figma_execute", params:$p,
                  file_key: (if $fk == "" then null else $fk end)}}')
fi

echo "$DESCRIPTOR"
exit 10
