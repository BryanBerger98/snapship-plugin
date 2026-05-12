#!/usr/bin/env bash
# figma-bridge-helper.sh — wrapper Bridge CLI (compilateur YAML CSpec → Figma Plugin API).
#
# Bridge (`bridge-ds`) compile des spécifications YAML déclaratives en code JS
# Plugin API conforme système design (26 règles Figma appliquées). Bridge n'est
# PAS un serveur MCP : c'est un CLI Node.js séparé, invoqué localement par ce
# helper. La sortie compilée est ensuite acheminée via le serveur
# figma-console-mcp (transport `official`) ou écrite sur disque pour collage
# manuel DevTools (transport `console`).
#
# Helper context-agnostic depuis v0.5: ne lit aucune configuration projet. Les
# params (--kb-path, --transport, --token-env) sont passés explicitement par le
# skill. Défauts internes: transport=official, token-env=FIGMA_TOKEN.
#
# Pour tests: env var SNAP_BRIDGE_DS_BIN override le binaire bridge-ds (stub
# possible). Si non défini, helper cherche `bridge-ds` sur PATH.
#
# Actions:
#   ds-init        --kb-path=DIR
#                  → bridge-ds setup --kb=DIR. Init structure KB système design.
#                    Local-only, pas d'injection Figma. Retourne {ok, kb_path}.
#   ds-update      --kb-path=DIR (--transport=official|console) (--output-js=PATH)
#                  → bridge-ds compile <kb> → JS conforme DS.
#                    transport=official : emet descriptor figma_execute MCP.
#                    transport=console  : écrit JS à --output-js, retourne instructions.
#   mockup-compile --kb-path=DIR --scene-graph-file=YAML (--transport=...) (--output-js=PATH)
#                  → bridge-ds compile <yaml> --kb=<kb>. Compile mockup CSpec.
#                    Routing identique ds-update.
#   extract-ds     --kb-path=DIR --file-key=KEY (--token-env=FIGMA_TOKEN)
#                  → bridge-ds extract --kb=DIR --file-key=KEY. Pull DS Figma → KB.
#                    Requiert variable env nommée par --token-env définie.
#   export-shape   --node-id=ID --output-path=PATH (--format png|svg|jpg|pdf, --scale 1..4)
#                  → emet descriptor figma_execute (exportAsync) directement.
#                    Transport toujours `official` (Bridge non impliqué dans export).
#                    Skill décode base64 + écrit fichier (cf. figma-helper save-export).
#
# Transport routing:
#   official → exit 10, {ok:false, mode:"mcp", descriptor:{tool:"figma_execute", code:"..."}}
#   console  → exit 0,  {ok:true, mode:"local", action:..., result:{output_js, instructions}}
#
# Output JSON shapes:
#   mcp:  {"ok":false,"mode":"mcp","reason":"mcp_required","descriptor":{...}}  exit 10
#   loc:  {"ok":true,"mode":"local","action":...,"result":{...}}                exit 0
#   dry:  {"ok":true,"mode":"dry-run","action":...,"result":{...}}              exit 0
#   err:  {"ok":false,"error":"..."}                                            exit 1|2

set -uo pipefail

ACTION=""
KB_PATH=""
SCENE_GRAPH_FILE=""
TRANSPORT=""
TOKEN_ENV=""
OUTPUT_JS=""
NODE_ID=""
OUTPUT_PATH=""
FILE_KEY=""
EXPORT_FORMAT=""
EXPORT_SCALE=""
DRY_RUN="${SNAP_DRY_RUN:-false}"

usage() {
  cat <<EOF
Usage: figma-bridge-helper.sh --action=ACTION [OPTIONS]

Actions:
  ds-init        --kb-path
  ds-update      --kb-path (--transport=official|console) (--output-js)
  mockup-compile --kb-path --scene-graph-file (--transport) (--output-js)
  extract-ds     --kb-path --file-key (--token-env)
  export-shape   --node-id --output-path (--format, --scale)

Options:
  --kb-path=DIR              Répertoire base de connaissance Bridge
  --scene-graph-file=PATH    Fichier YAML CSpec mockup (mockup-compile)
  --transport=MODE           official|console (défaut interne: official)
  --token-env=NAME           Nom var env contenant token Figma (défaut: FIGMA_TOKEN)
  --output-js=PATH           Fichier .js (transport console) ; défaut <kb-path>/build/out.js
  --node-id=ID               Figma node ID (export-shape)
  --output-path=PATH         Chemin asset exporté (export-shape)
  --file-key=KEY             Clé fichier Figma (extract-ds)
  --format=png|svg|jpg|pdf   Format export (défaut interne: png)
  --scale=1|2|3|4            Échelle export (défaut interne: 2)
  --dry-run                  Skip writes; équiv. \$SNAP_DRY_RUN=1
  -h, --help                 Affiche cette aide
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --action=*)             ACTION="${1#--action=}" ;;
    --kb-path=*)            KB_PATH="${1#--kb-path=}" ;;
    --scene-graph-file=*)   SCENE_GRAPH_FILE="${1#--scene-graph-file=}" ;;
    --transport=*)          TRANSPORT="${1#--transport=}" ;;
    --token-env=*)          TOKEN_ENV="${1#--token-env=}" ;;
    --output-js=*)          OUTPUT_JS="${1#--output-js=}" ;;
    --node-id=*)            NODE_ID="${1#--node-id=}" ;;
    --output-path=*)        OUTPUT_PATH="${1#--output-path=}" ;;
    --file-key=*)           FILE_KEY="${1#--file-key=}" ;;
    --format=*)             EXPORT_FORMAT="${1#--format=}" ;;
    --scale=*)              EXPORT_SCALE="${1#--scale=}" ;;
    --dry-run)              DRY_RUN="true" ;;
    -h|--help)              usage; exit 0 ;;
    *) echo "ERROR: unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required" >&2; exit 2; }
[ -z "$ACTION" ] && { echo "ERROR: --action required" >&2; exit 2; }

case "$ACTION" in
  ds-init|ds-update|mockup-compile|extract-ds|export-shape) ;;
  *) echo "ERROR: invalid --action: $ACTION" >&2; exit 2 ;;
esac

# Defaults internes — pas de lecture config.
[ -z "$TRANSPORT"  ] && TRANSPORT="official"
[ -z "$TOKEN_ENV"  ] && TOKEN_ENV="FIGMA_TOKEN"
[ -z "$EXPORT_FORMAT" ] && EXPORT_FORMAT="png"
[ -z "$EXPORT_SCALE"  ] && EXPORT_SCALE="2"

case "$TRANSPORT" in
  official|console) ;;
  *) echo "ERROR: bad --transport: $TRANSPORT (allowed: official|console)" >&2; exit 2 ;;
esac

# --- per-action validation -----------------------------------------------
need() { [ -n "$1" ] || { echo "ERROR: $2" >&2; exit 2; }; }

case "$ACTION" in
  ds-init)
    need "$KB_PATH" "--kb-path required for ds-init" ;;
  ds-update)
    need "$KB_PATH" "--kb-path required for ds-update"
    [ -d "$KB_PATH" ] || { echo "ERROR: kb-path not a directory: $KB_PATH" >&2; exit 1; } ;;
  mockup-compile)
    need "$KB_PATH" "--kb-path required for mockup-compile"
    need "$SCENE_GRAPH_FILE" "--scene-graph-file required for mockup-compile"
    [ -d "$KB_PATH" ] || { echo "ERROR: kb-path not a directory: $KB_PATH" >&2; exit 1; }
    [ -f "$SCENE_GRAPH_FILE" ] || { echo "ERROR: scene-graph-file not found: $SCENE_GRAPH_FILE" >&2; exit 1; } ;;
  extract-ds)
    need "$KB_PATH" "--kb-path required for extract-ds"
    need "$FILE_KEY" "--file-key required for extract-ds"
    if [ "$DRY_RUN" != "true" ] && [ -z "${!TOKEN_ENV:-}" ]; then
      echo "ERROR: env var \$$TOKEN_ENV not set (required for extract-ds)" >&2
      exit 1
    fi ;;
  export-shape)
    need "$NODE_ID" "--node-id required for export-shape"
    need "$OUTPUT_PATH" "--output-path required for export-shape"
    case "$EXPORT_FORMAT" in png|svg|jpg|pdf) ;; *) echo "ERROR: bad --format: $EXPORT_FORMAT (allowed: png|svg|jpg|pdf)" >&2; exit 2 ;; esac
    case "$EXPORT_SCALE" in 1|2|3|4) ;; *) echo "ERROR: bad --scale: $EXPORT_SCALE (allowed: 1|2|3|4)" >&2; exit 2 ;; esac ;;
esac

# --- bridge-ds binary resolution -----------------------------------------
BRIDGE_BIN="${SNAP_BRIDGE_DS_BIN:-}"
if [ -z "$BRIDGE_BIN" ]; then
  if command -v bridge-ds >/dev/null 2>&1; then
    BRIDGE_BIN="bridge-ds"
  fi
fi

needs_bridge_bin() {
  case "$1" in ds-init|ds-update|mockup-compile|extract-ds) return 0 ;; *) return 1 ;; esac
}

if needs_bridge_bin "$ACTION" && [ -z "$BRIDGE_BIN" ]; then
  echo "ERROR: bridge-ds CLI not found on PATH (install: npm i -g @bridge-ds/cli)" >&2
  exit 1
fi

# --- dry-run --------------------------------------------------------------
if [ "$DRY_RUN" = "true" ]; then
  MOCK=$(jq -nc --arg act "$ACTION" --arg kb "$KB_PATH" --arg yaml "$SCENE_GRAPH_FILE" \
                --arg trn "$TRANSPORT" --arg te "$TOKEN_ENV" --arg fk "$FILE_KEY" \
                --arg nid "$NODE_ID" --arg out "$OUTPUT_PATH" --arg fmt "$EXPORT_FORMAT" \
                --arg scl "$EXPORT_SCALE" --arg js "$OUTPUT_JS" '
    {dry_run:true, action:$act, transport:$trn}
    | if $kb   != "" then .kb_path = $kb else . end
    | if $yaml != "" then .scene_graph_file = $yaml else . end
    | if $te   != "" then .token_env = $te else . end
    | if $fk   != "" then .file_key = $fk else . end
    | if $nid  != "" then .node_id = $nid else . end
    | if $out  != "" then .output_path = $out else . end
    | if $js   != "" then .output_js = $js else . end
    | if $act == "export-shape" then .format = $fmt | .scale = ($scl|tonumber) else . end')
  jq -nc --argjson r "$MOCK" --arg act "$ACTION" '
    {ok:true, mode:"dry-run", action:$act, platform:"figma", result:$r}'
  exit 0
fi

# --- export-shape : delegate to figma_execute (Bridge non impliqué) ------
if [ "$ACTION" = "export-shape" ]; then
  local_fmt_upper=""
  case "$EXPORT_FORMAT" in
    png) local_fmt_upper="PNG" ;;
    svg) local_fmt_upper="SVG" ;;
    jpg) local_fmt_upper="JPG" ;;
    pdf) local_fmt_upper="PDF" ;;
  esac
  JS_CODE=$(jq -nc --arg nid "$NODE_ID" --arg fmt "$local_fmt_upper" --arg scl "$EXPORT_SCALE" '
    "const n = figma.getNodeById(" + ($nid | tojson) + "); if (!n) throw new Error(\"node not found\"); const bytes = await n.exportAsync({format:\"" + $fmt + "\", constraint:{type:\"SCALE\", value:" + $scl + "}}); ({node_id: n.id, format:\"" + $fmt + "\", data: figma.base64Encode(bytes)});"')
  PARAMS=$(jq -nc --argjson code "$JS_CODE" '{code:$code}')
  DESCRIPTOR=$(jq -nc --arg act "$ACTION" --argjson p "$PARAMS" \
                     --arg out "$OUTPUT_PATH" --arg fmt "$EXPORT_FORMAT" --arg scl "$EXPORT_SCALE" '
    {ok:false, mode:"mcp", reason:"mcp_required",
     descriptor: {platform:"figma", action:$act, tool:"figma_execute", params:$p,
                  result_path:$out, format:$fmt, scale:($scl|tonumber)}}')
  echo "$DESCRIPTOR"
  exit 10
fi

# --- ds-init : bridge-ds setup -------------------------------------------
if [ "$ACTION" = "ds-init" ]; then
  if ! SETUP_OUT=$("$BRIDGE_BIN" setup --kb="$KB_PATH" 2>&1); then
    echo "ERROR: bridge-ds setup failed: $SETUP_OUT" >&2
    exit 1
  fi
  jq -nc --arg kb "$KB_PATH" --arg log "$SETUP_OUT" '
    {ok:true, mode:"local", action:"ds-init", platform:"figma",
     result:{kb_path:$kb, log:$log}}'
  exit 0
fi

# --- extract-ds : bridge-ds extract --------------------------------------
if [ "$ACTION" = "extract-ds" ]; then
  if ! EXT_OUT=$("$BRIDGE_BIN" extract --kb="$KB_PATH" --file-key="$FILE_KEY" 2>&1); then
    echo "ERROR: bridge-ds extract failed: $EXT_OUT" >&2
    exit 1
  fi
  jq -nc --arg kb "$KB_PATH" --arg fk "$FILE_KEY" --arg te "$TOKEN_ENV" --arg log "$EXT_OUT" '
    {ok:true, mode:"local", action:"extract-ds", platform:"figma",
     result:{kb_path:$kb, file_key:$fk, token_env:$te, log:$log}}'
  exit 0
fi

# --- ds-update / mockup-compile : bridge-ds compile ----------------------
COMPILE_INPUT=""
case "$ACTION" in
  ds-update)      COMPILE_INPUT="$KB_PATH" ;;
  mockup-compile) COMPILE_INPUT="$SCENE_GRAPH_FILE" ;;
esac

if ! COMPILED_JS=$("$BRIDGE_BIN" compile "$COMPILE_INPUT" --kb="$KB_PATH" 2>/dev/null); then
  echo "ERROR: bridge-ds compile failed for $COMPILE_INPUT" >&2
  exit 1
fi

if [ -z "$COMPILED_JS" ]; then
  echo "ERROR: bridge-ds compile produced empty output" >&2
  exit 1
fi

# --- transport routing ---------------------------------------------------
if [ "$TRANSPORT" = "console" ]; then
  # Default output path under kb-path/build/ if not provided.
  if [ -z "$OUTPUT_JS" ]; then
    OUTPUT_JS="${KB_PATH%/}/build/$(basename "${COMPILE_INPUT}" | sed 's/\.[^.]*$//').js"
  fi
  mkdir -p "$(dirname "$OUTPUT_JS")" || { echo "ERROR: cannot create dir: $(dirname "$OUTPUT_JS")" >&2; exit 1; }
  printf '%s\n' "$COMPILED_JS" > "$OUTPUT_JS" || { echo "ERROR: write failed: $OUTPUT_JS" >&2; exit 1; }
  INSTRUCTIONS="Ouvrir Figma Desktop → menu Plugins → Development → Open Console. Coller le contenu de ${OUTPUT_JS} et exécuter (Enter)."
  jq -nc --arg act "$ACTION" --arg js "$OUTPUT_JS" --arg ins "$INSTRUCTIONS" \
         --arg kb "$KB_PATH" --arg sgf "$SCENE_GRAPH_FILE" '
    {ok:true, mode:"local", action:$act, platform:"figma", transport:"console",
     result:{output_js:$js, kb_path:$kb,
             scene_graph_file: (if $sgf == "" then null else $sgf end),
             instructions:$ins, injected:false}}'
  exit 0
fi

# transport = official → emit figma_execute descriptor with compiled JS
PARAMS=$(jq -nc --arg code "$COMPILED_JS" '{code:$code}')
DESCRIPTOR=$(jq -nc --arg act "$ACTION" --argjson p "$PARAMS" \
                   --arg kb "$KB_PATH" --arg sgf "$SCENE_GRAPH_FILE" '
  {ok:false, mode:"mcp", reason:"mcp_required",
   descriptor: {platform:"figma", action:$act, tool:"figma_execute", params:$p,
                transport:"official", kb_path:$kb,
                scene_graph_file: (if $sgf == "" then null else $sgf end)}}')
echo "$DESCRIPTOR"
exit 10
