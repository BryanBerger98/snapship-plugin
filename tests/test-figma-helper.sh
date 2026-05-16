#!/usr/bin/env bash
# Tests pour skills/_shared/figma-helper.sh

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/skills/_shared/figma-helper.sh"

PASS=0
FAIL=0
ERRORS=()

ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

cleanup() {
  [ -n "${TMP:-}" ] && [ -d "$TMP" ] && { trash "$TMP" 2>/dev/null || rm -rf "$TMP"; }
}
trap cleanup EXIT

unset SNAP_DRY_RUN SNAP_PROJECT_ROOT 2>/dev/null || true

echo "=== figma-helper.sh tests ==="

# --- [1] usage / arg parsing ---------------------------------------------
echo ""
echo "[1] help exit 0"
bash "$SCRIPT" --help >/dev/null 2>&1
[ $? -eq 0 ] && ok "1.1" || ko "1.1"

echo ""
echo "[2] missing --action"
bash "$SCRIPT" >/dev/null 2>&1
[ $? -eq 2 ] && ok "2.1" || ko "2.1"

echo ""
echo "[3] bad action"
bash "$SCRIPT" --action=foo >/dev/null 2>&1
[ $? -eq 2 ] && ok "3.1" || ko "3.1"

echo ""
echo "[4] per-action validation"
bash "$SCRIPT" --action=create-page >/dev/null 2>&1
[ $? -eq 2 ] && ok "4.1 create-page needs --title" || ko "4.1"

bash "$SCRIPT" --action=get-page >/dev/null 2>&1
[ $? -eq 2 ] && ok "4.2 get-page needs --page-id" || ko "4.2"

bash "$SCRIPT" --action=delete-page >/dev/null 2>&1
[ $? -eq 2 ] && ok "4.3 delete-page needs --page-id" || ko "4.3"

bash "$SCRIPT" --action=update-page --page-id=p >/dev/null 2>&1
[ $? -eq 2 ] && ok "4.4 update-page needs --title" || ko "4.4"

bash "$SCRIPT" --action=update-page --title=t >/dev/null 2>&1
[ $? -eq 2 ] && ok "4.5 update-page needs --page-id" || ko "4.5"

bash "$SCRIPT" --action=list-pages >/dev/null 2>&1
[ $? -eq 2 ] && ok "4.6 list-pages needs --query" || ko "4.6"

bash "$SCRIPT" --action=add-shapes >/dev/null 2>&1
[ $? -eq 2 ] && ok "4.7 add-shapes needs --page-id" || ko "4.7"

bash "$SCRIPT" --action=add-shapes --page-id=p >/dev/null 2>&1
[ $? -eq 2 ] && ok "4.8 add-shapes needs --shapes" || ko "4.8"

bash "$SCRIPT" --action=add-shapes --page-id=p --shapes='{"not":"array"}' >/dev/null 2>&1
[ $? -eq 2 ] && ok "4.9 add-shapes shapes must be array" || ko "4.9"

bash "$SCRIPT" --action=add-shapes --page-id=p --shapes='[]' --shapes-file=/tmp/x >/dev/null 2>&1
[ $? -eq 2 ] && ok "4.10 mutual exclusion --shapes/--shapes-file" || ko "4.10"

bash "$SCRIPT" --action=export-png >/dev/null 2>&1
[ $? -eq 2 ] && ok "4.11 export-png needs target" || ko "4.11"

bash "$SCRIPT" --action=export-png --shape-id=s >/dev/null 2>&1
[ $? -eq 2 ] && ok "4.12 export-png needs --output-path" || ko "4.12"

bash "$SCRIPT" --action=export-png --shape-id=s --output-path=/tmp/x.png --format=webp >/dev/null 2>&1
[ $? -eq 2 ] && ok "4.13 export-png rejects webp" || ko "4.13"

bash "$SCRIPT" --action=export-png --shape-id=s --output-path=/tmp/x.png --scale=5 >/dev/null 2>&1
[ $? -eq 2 ] && ok "4.14 export-png rejects scale=5" || ko "4.14"

bash "$SCRIPT" --action=export-png --shape-id=s --output-path=/tmp/x.png --scale=0 >/dev/null 2>&1
[ $? -eq 2 ] && ok "4.15 export-png rejects scale=0" || ko "4.15"

# Batch limit 100/call (figma_execute constraint)
BIG=$(jq -nc '[range(0;101)] | map({type:"rect", name:"r\(.)"})')
bash "$SCRIPT" --action=add-shapes --page-id=p --shapes="$BIG" >/dev/null 2>&1
[ $? -eq 2 ] && ok "4.16 add-shapes rejects >100 items" || ko "4.16"

OK100=$(jq -nc '[range(0;100)] | map({type:"rect", name:"r\(.)"})')
RC=$(bash "$SCRIPT" --action=add-shapes --page-id=p --shapes="$OK100" >/dev/null 2>&1; echo $?)
[ "$RC" -eq 10 ] && ok "4.17 add-shapes accepts exactly 100" || ko "4.17 rc=$RC"

# --- [5] create-page descriptor ------------------------------------------

echo ""
echo "[5] create-page emits figma_execute descriptor"
OUT=$(bash "$SCRIPT" --action=create-page --title='Sign Up Empty' 2>&1)
RC=$?
[ "$RC" -eq 10 ] && ok "5.1 exit 10" || ko "5.1 exit=$RC"
echo "$OUT" | jq -e '.descriptor.platform == "figma"' >/dev/null && ok "5.2 platform=figma" || ko "5.2"
echo "$OUT" | jq -e '.descriptor.action == "create-page"' >/dev/null && ok "5.3 action" || ko "5.3"
echo "$OUT" | jq -e '.descriptor.tool == "figma_execute"' >/dev/null && ok "5.4 tool=figma_execute" || ko "5.4"
echo "$OUT" | jq -e '.descriptor.params.code | contains("figma.createPage()")' >/dev/null && ok "5.5 JS includes createPage" || ko "5.5"
echo "$OUT" | jq -e '.descriptor.params.code | contains("\"Sign Up Empty\"")' >/dev/null && ok "5.6 JS embeds title" || ko "5.6"
echo "$OUT" | jq -e '.descriptor.file_key == null' >/dev/null && ok "5.7 file_key null when absent" || ko "5.7"

# --- [6] file_key propagation --------------------------------------------

echo ""
echo "[6] --file-key propagated as descriptor metadata"
OUT=$(bash "$SCRIPT" --action=create-page --title=X --file-key=ABC123 2>&1)
echo "$OUT" | jq -e '.descriptor.file_key == "ABC123"' >/dev/null && ok "6.1 file_key embedded" || ko "6.1"

# --- [7] export-png descriptor -------------------------------------------

echo ""
echo "[7] export-png descriptor"
OUT=$(bash "$SCRIPT" --action=export-png --page-id=1:23 --output-path=/abs/p.png 2>&1)
RC=$?
[ "$RC" -eq 10 ] && ok "7.1 exit 10" || ko "7.1 rc=$RC"
echo "$OUT" | jq -e '.descriptor.tool == "figma_execute"' >/dev/null && ok "7.2 tool=figma_execute" || ko "7.2"
echo "$OUT" | jq -e '.descriptor.result_path == "/abs/p.png"' >/dev/null && ok "7.3 result_path hint" || ko "7.3"
echo "$OUT" | jq -e '.descriptor.format == "png"' >/dev/null && ok "7.4 format hint" || ko "7.4"
echo "$OUT" | jq -e '.descriptor.scale == 2' >/dev/null && ok "7.5 scale default=2" || ko "7.5"
echo "$OUT" | jq -e '.descriptor.params.code | contains("exportAsync")' >/dev/null && ok "7.6 JS exportAsync" || ko "7.6"
echo "$OUT" | jq -e '.descriptor.params.code | contains("figma.base64Encode")' >/dev/null && ok "7.7 JS base64Encode" || ko "7.7"
echo "$OUT" | jq -e '.descriptor.params.code | contains("format:\"PNG\"")' >/dev/null && ok "7.8 PNG upper-case" || ko "7.8"
echo "$OUT" | jq -e '.descriptor.params.code | contains("value:2")' >/dev/null && ok "7.9 SCALE constraint embedded" || ko "7.9"

echo ""
echo "[8] export-png --shape-id takes precedence over --page-id"
OUT=$(bash "$SCRIPT" --action=export-png --shape-id=99:88 --page-id=1:1 --output-path=/abs/s.png 2>&1)
echo "$OUT" | jq -e '.descriptor.params.code | contains("getNodeById(\"99:88\")")' >/dev/null && ok "8.1 shape-id wins" || ko "8.1"

echo ""
echo "[9] export-png alternate formats"
for FMT in svg jpg pdf; do
  UPPER=$(echo "$FMT" | tr '[:lower:]' '[:upper:]')
  OUT=$(bash "$SCRIPT" --action=export-png --shape-id=s --output-path=/abs/x.$FMT --format="$FMT" 2>&1)
  RC=$?
  [ "$RC" -eq 10 ] && ok "9.$FMT exit 10" || ko "9.$FMT rc=$RC"
  echo "$OUT" | jq -e --arg u "$UPPER" '.descriptor.params.code | contains("format:\"" + $u + "\"")' >/dev/null \
    && ok "9.$FMT upper-cased in JS" || ko "9.$FMT not upper"
  echo "$OUT" | jq -e --arg f "$FMT" '.descriptor.format == $f' >/dev/null && ok "9.$FMT format hint" || ko "9.$FMT hint"
done

echo ""
echo "[10] export-png scales 1..4"
for S in 1 2 3 4; do
  OUT=$(bash "$SCRIPT" --action=export-png --shape-id=s --output-path=/abs/x.png --scale="$S" 2>&1)
  echo "$OUT" | jq -e --arg s "$S" '.descriptor.params.code | contains("value:" + $s)' >/dev/null \
    && ok "10.$S scale=$S" || ko "10.$S"
done

# --- [11] add-shapes JS construction -------------------------------------

echo ""
echo "[11] add-shapes JS body — text/rect/ellipse paths"
OUT=$(bash "$SCRIPT" --action=add-shapes --page-id=0:5 \
  --shapes='[{"type":"text","name":"Title","x":40,"y":40,"width":200,"height":40,"text":"Hi","fill":"#000000"},{"type":"rect","name":"Bg","x":0,"y":0,"width":300,"height":200},{"type":"ellipse","name":"Dot","x":5,"y":5,"width":20,"height":20,"fill":"#ff0000"}]' 2>&1)
RC=$?
[ "$RC" -eq 10 ] && ok "11.1 exit 10" || ko "11.1 rc=$RC"
JS=$(echo "$OUT" | jq -r '.descriptor.params.code')
echo "$JS" | grep -q 'getNodeById("0:5")' && ok "11.2 page lookup" || ko "11.2"
echo "$JS" | grep -q 'figma.currentPage = page' && ok "11.3 switch currentPage" || ko "11.3"
echo "$JS" | grep -q 'loadFontAsync' && ok "11.4 loadFontAsync for text" || ko "11.4"
echo "$JS" | grep -q 'figma.createText()' && ok "11.5 createText" || ko "11.5"
echo "$JS" | grep -q 'figma.createRectangle()' && ok "11.6 createRectangle" || ko "11.6"
echo "$JS" | grep -q 'figma.createEllipse()' && ok "11.7 createEllipse" || ko "11.7"
echo "$JS" | grep -q '"Title"' && ok "11.8 shape name embedded" || ko "11.8"
echo "$JS" | grep -q 'hexToRgb' && ok "11.9 hex→rgb helper" || ko "11.9"
echo "$JS" | grep -q 'type:"SOLID"' && ok "11.10 SOLID paint" || ko "11.10"
echo "$JS" | grep -q 'page.appendChild(shape)' && ok "11.11 appendChild" || ko "11.11"

echo ""
echo "[12] add-shapes from --shapes-file"
TMP=$(mktemp -d)
SF="$TMP/shapes.json"
cat > "$SF" <<'EOF'
[{"type":"ellipse","name":"Avatar","x":10,"y":10,"width":40,"height":40,"fill":"#ddd"}]
EOF
# Note: Figma rejects 3-char hex; helper just passes whatever fill JS regex accepts.
OUT=$(bash "$SCRIPT" --action=add-shapes --page-id=p --shapes-file="$SF" 2>&1)
RC=$?
[ "$RC" -eq 10 ] && ok "12.1 file load ok" || ko "12.1 rc=$RC"
echo "$OUT" | jq -e '.descriptor.params.code | contains("createEllipse")' >/dev/null && ok "12.2 ellipse path" || ko "12.2"

bash "$SCRIPT" --action=add-shapes --page-id=p --shapes-file="$TMP/missing.json" >/dev/null 2>&1
[ $? -eq 1 ] && ok "12.3 missing file exit 1" || ko "12.3"

# --- [13] read/update/delete/list actions --------------------------------

echo ""
echo "[13] get/update/delete/list descriptors"
OUT=$(bash "$SCRIPT" --action=get-page --page-id=0:1 2>&1)
[ $? -eq 10 ] && ok "13.1 get-page exit 10" || ko "13.1"
echo "$OUT" | jq -e '.descriptor.params.code | contains("getNodeById")' >/dev/null && ok "13.2 getNodeById" || ko "13.2"
echo "$OUT" | jq -e '.descriptor.params.code | contains("type === \"PAGE\"")' >/dev/null && ok "13.3 PAGE type check" || ko "13.3"

OUT=$(bash "$SCRIPT" --action=update-page --page-id=0:1 --title='New' 2>&1)
[ $? -eq 10 ] && ok "13.4 update-page exit 10" || ko "13.4"
echo "$OUT" | jq -e '.descriptor.params.code | contains("\"New\"")' >/dev/null && ok "13.5 title embed" || ko "13.5"

OUT=$(bash "$SCRIPT" --action=delete-page --page-id=0:1 2>&1)
[ $? -eq 10 ] && ok "13.6 delete-page exit 10" || ko "13.6"
echo "$OUT" | jq -e '.descriptor.params.code | contains("n.remove()")' >/dev/null && ok "13.7 n.remove()" || ko "13.7"

OUT=$(bash "$SCRIPT" --action=list-pages --query=home --limit=5 2>&1)
[ $? -eq 10 ] && ok "13.8 list-pages exit 10" || ko "13.8"
echo "$OUT" | jq -e '.descriptor.params.code | contains("figma.root.children")' >/dev/null && ok "13.9 root.children" || ko "13.9"
echo "$OUT" | jq -e '.descriptor.params.code | contains(".slice(0, 5)")' >/dev/null && ok "13.10 limit applied" || ko "13.10"

# --- [14] dry-run --------------------------------------------------------

echo ""
echo "[14] dry-run short-circuits writes"
OUT=$(SNAP_DRY_RUN=true bash "$SCRIPT" --action=create-page --title=DryX 2>&1)
[ $? -eq 0 ] && ok "14.1 create-page dry-run exit 0" || ko "14.1"
echo "$OUT" | jq -e '.mode == "dry-run"' >/dev/null && ok "14.2 mode" || ko "14.2"
echo "$OUT" | jq -e '.platform == "figma"' >/dev/null && ok "14.3 platform=figma" || ko "14.3"

OUT=$(bash "$SCRIPT" --dry-run --action=export-png --shape-id=s --output-path=/abs/x.png 2>&1)
[ $? -eq 0 ] && ok "14.4 export-png dry-run exit 0" || ko "14.4"
echo "$OUT" | jq -e '.result.written == false' >/dev/null && ok "14.5 written=false" || ko "14.5"
echo "$OUT" | jq -e '.result.format == "png"' >/dev/null && ok "14.6 result.format" || ko "14.6"
echo "$OUT" | jq -e '.result.scale == 2' >/dev/null && ok "14.7 result.scale" || ko "14.7"

OUT=$(SNAP_DRY_RUN=true bash "$SCRIPT" --action=add-shapes --page-id=p --shapes='[]' 2>&1)
[ $? -eq 0 ] && ok "14.8 add-shapes dry-run" || ko "14.8"

OUT=$(SNAP_DRY_RUN=true bash "$SCRIPT" --action=update-page --page-id=p --title=Z 2>&1)
[ $? -eq 0 ] && ok "14.9 update-page dry-run" || ko "14.9"

OUT=$(SNAP_DRY_RUN=true bash "$SCRIPT" --action=delete-page --page-id=p 2>&1)
[ $? -eq 0 ] && ok "14.10 delete-page dry-run" || ko "14.10"

# --- [15] read actions ignore dry-run -----------------------------------

echo ""
echo "[15] dry-run does NOT short-circuit read actions"
OUT=$(SNAP_DRY_RUN=true bash "$SCRIPT" --action=get-page --page-id=p 2>&1)
[ $? -eq 10 ] && ok "15.1 get-page still emits descriptor" || ko "15.1"

OUT=$(SNAP_DRY_RUN=true bash "$SCRIPT" --action=list-pages --query=x 2>&1)
[ $? -eq 10 ] && ok "15.2 list-pages still emits descriptor" || ko "15.2"

# --- [16] context-agnostic — pas de lecture config ----------------------

echo ""
echo "[16] export-png défaut interne png/scale=2, config ignorée"
CFG_DIR=$(mktemp -d)
cat > "$CFG_DIR/snap.config.json" <<'EOF'
{"version":"1.0","wireframes":{"platform":"figma","export_format":"svg"}}
EOF
OUT=$(bash "$SCRIPT" --action=export-png --shape-id=s --output-path=/abs/x.png 2>&1)
RC=$?
[ "$RC" -eq 10 ] && ok "16.1 descriptor emitted" || ko "16.1 rc=$RC"
echo "$OUT" | jq -e '.descriptor.format == "png"' >/dev/null && ok "16.2 défaut png (config ignorée)" || ko "16.2"
echo "$OUT" | jq -e '.descriptor.scale == 2' >/dev/null && ok "16.3 défaut scale=2" || ko "16.3"
OUT=$(bash "$SCRIPT" --action=export-png --shape-id=s --output-path=/abs/x.svg --format=svg --scale=3 2>&1)
echo "$OUT" | jq -e '.descriptor.format == "svg"' >/dev/null && ok "16.4 explicit --format=svg" || ko "16.4"
echo "$OUT" | jq -e '.descriptor.scale == 3' >/dev/null && ok "16.5 explicit --scale=3" || ko "16.5"
trash "$CFG_DIR" 2>/dev/null || rm -rf "$CFG_DIR"

# --- [17] get-current-file preflight ------------------------------------

echo ""
echo "[17] get-current-file no-arg preflight"
OUT=$(bash "$SCRIPT" --action=get-current-file 2>&1)
RC=$?
[ "$RC" -eq 10 ] && ok "17.1 exit 10" || ko "17.1 rc=$RC"
echo "$OUT" | jq -e '.descriptor.tool == "figma_execute"' >/dev/null && ok "17.2 tool=figma_execute" || ko "17.2"
echo "$OUT" | jq -e '.descriptor.action == "get-current-file"' >/dev/null && ok "17.3 action" || ko "17.3"
echo "$OUT" | jq -e '.descriptor.params.code | contains("figma.fileKey")' >/dev/null && ok "17.4 figma.fileKey in JS" || ko "17.4"
echo "$OUT" | jq -e '.descriptor.params.code | contains("figma.root.name")' >/dev/null && ok "17.5 figma.root.name in JS" || ko "17.5"

echo ""
echo "[18] get-current-file unaffected by dry-run (read action)"
OUT=$(SNAP_DRY_RUN=true bash "$SCRIPT" --action=get-current-file 2>&1)
[ $? -eq 10 ] && ok "18.1 still emits descriptor" || ko "18.1"

# --- [19] save-export — local décode base64 -----------------------------

echo ""
echo "[19] save-export decodes base64 to disk"
TMP=${TMP:-$(mktemp -d)}
OUT_PNG="$TMP/decoded.png"
PNG_B64="iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNgAAIAAAUAAeImBZsAAAAASUVORK5CYII="
RES=$(bash "$SCRIPT" --action=save-export --output-path="$OUT_PNG" --base64-data="$PNG_B64" 2>&1)
RC=$?
[ "$RC" -eq 0 ] && ok "19.1 exit 0" || ko "19.1 rc=$RC"
[ -s "$OUT_PNG" ] && ok "19.2 file written non-empty" || ko "19.2"
# PNG magic byte check
head -c 4 "$OUT_PNG" | od -An -c | grep -q '211   P   N   G' && ok "19.3 PNG signature" || ko "19.3"
echo "$RES" | jq -e '.ok == true' >/dev/null && ok "19.4 ok=true" || ko "19.4"
echo "$RES" | jq -e '.mode == "local"' >/dev/null && ok "19.5 mode=local" || ko "19.5"

echo ""
echo "[20] save-export from --base64-file"
B64F="$TMP/payload.b64"
echo -n "$PNG_B64" > "$B64F"
OUT_PNG2="$TMP/decoded2.png"
bash "$SCRIPT" --action=save-export --output-path="$OUT_PNG2" --base64-file="$B64F" >/dev/null 2>&1
RC=$?
[ "$RC" -eq 0 ] && ok "20.1 exit 0" || ko "20.1 rc=$RC"
[ -s "$OUT_PNG2" ] && ok "20.2 file written" || ko "20.2"

echo ""
echo "[21] save-export from stdin"
OUT_PNG3="$TMP/decoded3.png"
echo -n "$PNG_B64" | bash "$SCRIPT" --action=save-export --output-path="$OUT_PNG3" --base64-stdin >/dev/null 2>&1
RC=$?
[ "$RC" -eq 0 ] && ok "21.1 exit 0" || ko "21.1 rc=$RC"
[ -s "$OUT_PNG3" ] && ok "21.2 file written" || ko "21.2"

echo ""
echo "[22] save-export strips data URI prefix"
OUT_PNG4="$TMP/decoded4.png"
bash "$SCRIPT" --action=save-export --output-path="$OUT_PNG4" \
  --base64-data="data:image/png;base64,$PNG_B64" >/dev/null 2>&1
[ -s "$OUT_PNG4" ] && ok "22.1 prefix stripped + decode ok" || ko "22.1"

echo ""
echo "[23] save-export validation"
bash "$SCRIPT" --action=save-export >/dev/null 2>&1
[ $? -eq 2 ] && ok "23.1 needs --output-path" || ko "23.1"

bash "$SCRIPT" --action=save-export --output-path=/tmp/x.png >/dev/null 2>&1
[ $? -eq 2 ] && ok "23.2 needs a base64 source" || ko "23.2"

bash "$SCRIPT" --action=save-export --output-path=/tmp/x.png --base64-data=AA --base64-file=/tmp/y >/dev/null 2>&1
[ $? -eq 2 ] && ok "23.3 mutual exclusion data/file" || ko "23.3"

bash "$SCRIPT" --action=save-export --output-path=/tmp/x.png --base64-file=/no/such/file.b64 >/dev/null 2>&1
[ $? -eq 1 ] && ok "23.4 missing file exit 1" || ko "23.4"

echo ""
echo "[24] save-export rejects empty/invalid base64"
bash "$SCRIPT" --action=save-export --output-path="$TMP/empty.bin" --base64-data="" --base64-stdin >/dev/null 2>&1
RC=$?
[ "$RC" -ne 0 ] && ok "24.1 empty payload rejected" || ko "24.1"

# Invalid base64 → decode failure
bash "$SCRIPT" --action=save-export --output-path="$TMP/bad.bin" --base64-data="@@@not-base64@@@" >/dev/null 2>&1
RC=$?
[ "$RC" -eq 1 ] && ok "24.2 invalid base64 exit 1" || ko "24.2 rc=$RC"

# --- [25] export-png never bypasses MCP (no HTTP fallback) --------------

echo ""
echo "[25] export-png always emits MCP descriptor (no local fallback)"
OUT=$(bash "$SCRIPT" --action=export-png --shape-id=s --output-path=/abs/x.png 2>&1)
[ $? -eq 10 ] && ok "25.1 always exit 10" || ko "25.1"
echo "$OUT" | jq -e '.mode == "mcp"' >/dev/null && ok "25.2 mode=mcp" || ko "25.2"

# --- summary --------------------------------------------------------------

echo ""
echo "=== Summary ==="
echo "PASS: $PASS"
echo "FAIL: $FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "Failures:"
  for e in "${ERRORS[@]}"; do echo "  - $e"; done
  exit 1
fi
exit 0
