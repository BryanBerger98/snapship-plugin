#!/usr/bin/env bash
# Tests pour skills/_shared/figma-bridge-helper.sh

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/skills/_shared/figma-bridge-helper.sh"

PASS=0
FAIL=0
ERRORS=()

ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

TMP=$(mktemp -d)
cleanup() { [ -d "$TMP" ] && { trash "$TMP" 2>/dev/null || rm -rf "$TMP"; }; }
trap cleanup EXIT

unset SNAP_DRY_RUN SNAP_PROJECT_ROOT FIGMA_ACCESS_TOKEN FIGMA_TOKEN 2>/dev/null || true

# --- bridge-ds stub binary ----------------------------------------------
# Simule les sorties principales de bridge-ds pour les tests.
STUB="$TMP/bridge-ds-stub.sh"
cat > "$STUB" <<'STUBEOF'
#!/usr/bin/env bash
CMD="$1"; shift
case "$CMD" in
  setup)
    KB=""
    for a in "$@"; do
      case "$a" in --kb=*) KB="${a#--kb=}";; esac
    done
    [ -n "$KB" ] && mkdir -p "$KB"
    echo "Bridge KB initialized at $KB"
    exit 0
    ;;
  compile)
    INPUT="$1"; shift
    KB=""
    for a in "$@"; do case "$a" in --kb=*) KB="${a#--kb=}";; esac; done
    if [ -z "$INPUT" ]; then echo "no input" >&2; exit 1; fi
    if [ -n "${SNAP_BRIDGE_STUB_FAIL_COMPILE:-}" ]; then
      echo "stub compile failure forced" >&2
      exit 1
    fi
    if [ -n "${SNAP_BRIDGE_STUB_EMPTY:-}" ]; then
      exit 0
    fi
    printf '// compiled by bridge-ds stub\nconsole.log("kb=%s input=%s");\n' "$KB" "$INPUT"
    exit 0
    ;;
  extract)
    KB=""; FK=""
    for a in "$@"; do
      case "$a" in
        --kb=*) KB="${a#--kb=}" ;;
        --file-key=*) FK="${a#--file-key=}" ;;
      esac
    done
    if [ -n "${SNAP_BRIDGE_STUB_FAIL_EXTRACT:-}" ]; then
      echo "stub extract failure" >&2
      exit 1
    fi
    echo "Extracted DS kb=$KB file-key=$FK"
    exit 0
    ;;
  *)
    echo "unknown bridge command: $CMD" >&2
    exit 1
    ;;
esac
STUBEOF
chmod +x "$STUB"
export SNAP_BRIDGE_DS_BIN="$STUB"

echo "=== figma-bridge-helper.sh tests ==="

# --- [1] usage / arg parsing --------------------------------------------

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
echo "[4] bad --transport"
bash "$SCRIPT" --action=ds-init --kb-path="$TMP/kb" --transport=invalid >/dev/null 2>&1
[ $? -eq 2 ] && ok "4.1 transport rejected" || ko "4.1"

echo ""
echo "[5] per-action validation"
bash "$SCRIPT" --action=ds-init >/dev/null 2>&1
[ $? -eq 2 ] && ok "5.1 ds-init needs --kb-path" || ko "5.1"

bash "$SCRIPT" --action=ds-update >/dev/null 2>&1
[ $? -eq 2 ] && ok "5.2 ds-update needs --kb-path" || ko "5.2"

bash "$SCRIPT" --action=ds-update --kb-path="$TMP/nope" >/dev/null 2>&1
[ $? -eq 1 ] && ok "5.3 ds-update rejects missing kb-path dir" || ko "5.3"

bash "$SCRIPT" --action=mockup-compile --kb-path="$TMP/kb" >/dev/null 2>&1
[ $? -eq 2 ] && ok "5.4 mockup-compile needs --scene-graph-file" || ko "5.4"

bash "$SCRIPT" --action=extract-ds --file-key=K >/dev/null 2>&1
[ $? -eq 2 ] && ok "5.5 extract-ds needs --kb-path" || ko "5.5"

bash "$SCRIPT" --action=extract-ds --kb-path="$TMP/kb" >/dev/null 2>&1
[ $? -eq 2 ] && ok "5.6 extract-ds needs --file-key" || ko "5.6"

bash "$SCRIPT" --action=export-shape --output-path=/tmp/x.png >/dev/null 2>&1
[ $? -eq 2 ] && ok "5.7 export-shape needs --node-id" || ko "5.7"

bash "$SCRIPT" --action=export-shape --node-id=1:5 >/dev/null 2>&1
[ $? -eq 2 ] && ok "5.8 export-shape needs --output-path" || ko "5.8"

bash "$SCRIPT" --action=export-shape --node-id=1:5 --output-path=/tmp/x.png --format=webp >/dev/null 2>&1
[ $? -eq 2 ] && ok "5.9 export-shape rejects webp" || ko "5.9"

bash "$SCRIPT" --action=export-shape --node-id=1:5 --output-path=/tmp/x.png --scale=5 >/dev/null 2>&1
[ $? -eq 2 ] && ok "5.10 export-shape rejects scale=5" || ko "5.10"

# --- [6] ds-init -------------------------------------------------------

echo ""
echo "[6] ds-init invokes bridge-ds setup"
mkdir -p "$TMP/kb6"
OUT=$(bash "$SCRIPT" --action=ds-init --kb-path="$TMP/kb6" 2>&1)
RC=$?
[ "$RC" -eq 0 ] && ok "6.1 exit 0" || ko "6.1 rc=$RC"
echo "$OUT" | jq -e '.ok == true' >/dev/null && ok "6.2 ok=true" || ko "6.2"
echo "$OUT" | jq -e '.action == "ds-init"' >/dev/null && ok "6.3 action" || ko "6.3"
echo "$OUT" | jq -e '.mode == "local"' >/dev/null && ok "6.4 mode=local" || ko "6.4"
echo "$OUT" | jq -e --arg kb "$TMP/kb6" '.result.kb_path == $kb' >/dev/null && ok "6.5 kb_path" || ko "6.5"

# --- [7] ds-init bridge-ds failure -------------------------------------

echo ""
echo "[7] ds-init bridge-ds failure → exit 1"
FAIL_BIN="$TMP/fail-bridge.sh"
cat > "$FAIL_BIN" <<'EOF'
#!/usr/bin/env bash
echo "intentional failure" >&2
exit 1
EOF
chmod +x "$FAIL_BIN"
SNAP_BRIDGE_DS_BIN="$FAIL_BIN" bash "$SCRIPT" --action=ds-init --kb-path="$TMP/kbfail" >/dev/null 2>&1
[ $? -eq 1 ] && ok "7.1 surface failure" || ko "7.1"

# --- [8] ds-update transport=official → descriptor ---------------------

echo ""
echo "[8] ds-update transport=official emits figma_execute descriptor"
mkdir -p "$TMP/kb8"
OUT=$(bash "$SCRIPT" --action=ds-update --kb-path="$TMP/kb8" 2>&1)
RC=$?
[ "$RC" -eq 10 ] && ok "8.1 exit 10" || ko "8.1 rc=$RC"
echo "$OUT" | jq -e '.descriptor.platform == "figma"' >/dev/null && ok "8.2 platform=figma" || ko "8.2"
echo "$OUT" | jq -e '.descriptor.action == "ds-update"' >/dev/null && ok "8.3 action" || ko "8.3"
echo "$OUT" | jq -e '.descriptor.tool == "figma_execute"' >/dev/null && ok "8.4 tool=figma_execute" || ko "8.4"
echo "$OUT" | jq -e '.descriptor.transport == "official"' >/dev/null && ok "8.5 transport=official" || ko "8.5"
echo "$OUT" | jq -e '.descriptor.params.code | contains("bridge-ds stub")' >/dev/null && ok "8.6 compiled JS embedded" || ko "8.6"

# --- [9] ds-update transport=console → writes JS file ------------------

echo ""
echo "[9] ds-update transport=console writes JS file"
mkdir -p "$TMP/kb9"
OUT_JS="$TMP/build9.js"
OUT=$(bash "$SCRIPT" --action=ds-update --kb-path="$TMP/kb9" --transport=console --output-js="$OUT_JS" 2>&1)
RC=$?
[ "$RC" -eq 0 ] && ok "9.1 exit 0" || ko "9.1 rc=$RC"
[ -s "$OUT_JS" ] && ok "9.2 JS file written non-empty" || ko "9.2"
grep -q 'bridge-ds stub' "$OUT_JS" && ok "9.3 file contains compiled JS" || ko "9.3"
echo "$OUT" | jq -e '.mode == "local"' >/dev/null && ok "9.4 mode=local" || ko "9.4"
echo "$OUT" | jq -e '.transport == "console"' >/dev/null && ok "9.5 transport=console" || ko "9.5"
echo "$OUT" | jq -e --arg js "$OUT_JS" '.result.output_js == $js' >/dev/null && ok "9.6 output_js path" || ko "9.6"
echo "$OUT" | jq -e '.result.injected == false' >/dev/null && ok "9.7 injected=false" || ko "9.7"
echo "$OUT" | jq -e '.result.instructions | contains("DevTools") or contains("Console")' >/dev/null && ok "9.8 instructions présentes" || ko "9.8"

# --- [10] ds-update console default output path -------------------------

echo ""
echo "[10] ds-update console without --output-js uses default kb/build/"
mkdir -p "$TMP/kb10"
OUT=$(bash "$SCRIPT" --action=ds-update --kb-path="$TMP/kb10" --transport=console 2>&1)
RC=$?
[ "$RC" -eq 0 ] && ok "10.1 exit 0" || ko "10.1 rc=$RC"
DEFAULT_JS=$(echo "$OUT" | jq -r '.result.output_js')
case "$DEFAULT_JS" in
  "$TMP/kb10/build/"*.js) ok "10.2 default under kb-path/build/" ;;
  *) ko "10.2 unexpected default: $DEFAULT_JS" ;;
esac
[ -s "$DEFAULT_JS" ] && ok "10.3 default file written" || ko "10.3"

# --- [11] mockup-compile --------------------------------------------------

echo ""
echo "[11] mockup-compile transport=official"
mkdir -p "$TMP/kb11"
YAML="$TMP/mockup.yaml"
cat > "$YAML" <<'EOF'
component: SignUpScreen
slots:
  title: "Sign up"
EOF
OUT=$(bash "$SCRIPT" --action=mockup-compile --kb-path="$TMP/kb11" --scene-graph-file="$YAML" 2>&1)
RC=$?
[ "$RC" -eq 10 ] && ok "11.1 exit 10" || ko "11.1 rc=$RC"
echo "$OUT" | jq -e '.descriptor.action == "mockup-compile"' >/dev/null && ok "11.2 action" || ko "11.2"
echo "$OUT" | jq -e --arg sgf "$YAML" '.descriptor.scene_graph_file == $sgf' >/dev/null && ok "11.3 scene_graph_file" || ko "11.3"
echo "$OUT" | jq -e '.descriptor.params.code | contains("bridge-ds stub")' >/dev/null && ok "11.4 compiled JS" || ko "11.4"

echo ""
echo "[12] mockup-compile transport=console"
OUT=$(bash "$SCRIPT" --action=mockup-compile --kb-path="$TMP/kb11" --scene-graph-file="$YAML" --transport=console --output-js="$TMP/mockup12.js" 2>&1)
RC=$?
[ "$RC" -eq 0 ] && ok "12.1 exit 0" || ko "12.1 rc=$RC"
[ -s "$TMP/mockup12.js" ] && ok "12.2 mockup JS written" || ko "12.2"
echo "$OUT" | jq -e --arg sgf "$YAML" '.result.scene_graph_file == $sgf' >/dev/null && ok "12.3 scene_graph_file in result" || ko "12.3"

echo ""
echo "[13] mockup-compile rejects missing scene-graph-file"
bash "$SCRIPT" --action=mockup-compile --kb-path="$TMP/kb11" --scene-graph-file="$TMP/nope.yaml" >/dev/null 2>&1
[ $? -eq 1 ] && ok "13.1 exit 1" || ko "13.1"

# --- [14] extract-ds requires token env --------------------------------

echo ""
echo "[14] extract-ds requires --token-env var set"
mkdir -p "$TMP/kb14"
# FIGMA_ACCESS_TOKEN unset (default)
bash "$SCRIPT" --action=extract-ds --kb-path="$TMP/kb14" --file-key=ABC >/dev/null 2>&1
[ $? -eq 1 ] && ok "14.1 missing token env exit 1" || ko "14.1"

# Set FIGMA_ACCESS_TOKEN → success
OUT=$(FIGMA_ACCESS_TOKEN="figd_test" bash "$SCRIPT" --action=extract-ds --kb-path="$TMP/kb14" --file-key=ABC 2>&1)
RC=$?
[ "$RC" -eq 0 ] && ok "14.2 exit 0 when token set" || ko "14.2 rc=$RC"
echo "$OUT" | jq -e '.ok == true' >/dev/null && ok "14.3 ok=true" || ko "14.3"
echo "$OUT" | jq -e '.result.file_key == "ABC"' >/dev/null && ok "14.4 file_key" || ko "14.4"
echo "$OUT" | jq -e '.result.token_env == "FIGMA_ACCESS_TOKEN"' >/dev/null && ok "14.5 token_env" || ko "14.5"

# Custom --token-env
OUT=$(MY_FIGMA_TOKEN="x" bash "$SCRIPT" --action=extract-ds --kb-path="$TMP/kb14" --file-key=ABC --token-env=MY_FIGMA_TOKEN 2>&1)
echo "$OUT" | jq -e '.result.token_env == "MY_FIGMA_TOKEN"' >/dev/null && ok "14.6 custom token env" || ko "14.6"

# --- [15] extract-ds bridge-ds failure -----------------------------------

echo ""
echo "[15] extract-ds bridge-ds failure → exit 1"
SNAP_BRIDGE_STUB_FAIL_EXTRACT=1 FIGMA_ACCESS_TOKEN=x bash "$SCRIPT" --action=extract-ds --kb-path="$TMP/kb14" --file-key=ABC >/dev/null 2>&1
[ $? -eq 1 ] && ok "15.1 exit 1" || ko "15.1"

# --- [16] compile failure handling --------------------------------------

echo ""
echo "[16] compile failure surfaces error"
mkdir -p "$TMP/kb16"
SNAP_BRIDGE_STUB_FAIL_COMPILE=1 bash "$SCRIPT" --action=ds-update --kb-path="$TMP/kb16" >/dev/null 2>&1
[ $? -eq 1 ] && ok "16.1 compile fail exit 1" || ko "16.1"

echo ""
echo "[17] compile empty output → exit 1"
SNAP_BRIDGE_STUB_EMPTY=1 bash "$SCRIPT" --action=ds-update --kb-path="$TMP/kb16" >/dev/null 2>&1
[ $? -eq 1 ] && ok "17.1 empty compile exit 1" || ko "17.1"

# --- [18] export-shape descriptor (Bridge non impliqué) ----------------

echo ""
echo "[18] export-shape emits figma_execute (no bridge-ds call)"
OUT=$(bash "$SCRIPT" --action=export-shape --node-id=99:42 --output-path=/abs/shape.png 2>&1)
RC=$?
[ "$RC" -eq 10 ] && ok "18.1 exit 10" || ko "18.1 rc=$RC"
echo "$OUT" | jq -e '.descriptor.tool == "figma_execute"' >/dev/null && ok "18.2 tool" || ko "18.2"
echo "$OUT" | jq -e '.descriptor.action == "export-shape"' >/dev/null && ok "18.3 action" || ko "18.3"
echo "$OUT" | jq -e '.descriptor.result_path == "/abs/shape.png"' >/dev/null && ok "18.4 result_path" || ko "18.4"
echo "$OUT" | jq -e '.descriptor.params.code | contains("getNodeById(\"99:42\")")' >/dev/null && ok "18.5 node id embed" || ko "18.5"
echo "$OUT" | jq -e '.descriptor.params.code | contains("exportAsync")' >/dev/null && ok "18.6 exportAsync" || ko "18.6"
echo "$OUT" | jq -e '.descriptor.params.code | contains("figma.base64Encode")' >/dev/null && ok "18.7 base64Encode" || ko "18.7"

echo ""
echo "[19] export-shape works without bridge-ds on PATH"
# Unset stub binary to confirm bridge-ds not required for export-shape.
SNAP_BRIDGE_DS_BIN=/nonexistent/bridge bash "$SCRIPT" --action=export-shape --node-id=1:1 --output-path=/abs/x.png >/dev/null 2>&1
[ $? -eq 10 ] && ok "19.1 exit 10 sans bridge-ds" || ko "19.1"

echo ""
echo "[20] export-shape alternate format + scale"
OUT=$(bash "$SCRIPT" --action=export-shape --node-id=1:1 --output-path=/abs/x.svg --format=svg --scale=3 2>&1)
echo "$OUT" | jq -e '.descriptor.format == "svg"' >/dev/null && ok "20.1 format=svg" || ko "20.1"
echo "$OUT" | jq -e '.descriptor.scale == 3' >/dev/null && ok "20.2 scale=3" || ko "20.2"
echo "$OUT" | jq -e '.descriptor.params.code | contains("format:\"SVG\"")' >/dev/null && ok "20.3 SVG upper" || ko "20.3"

# --- [21] missing bridge-ds binary --------------------------------------

echo ""
echo "[21] missing bridge-ds binary → exit 1 for bridge actions"
SNAP_BRIDGE_DS_BIN=/nonexistent/bridge-ds bash "$SCRIPT" --action=ds-init --kb-path="$TMP/kb21" >/dev/null 2>&1
[ $? -eq 1 ] && ok "21.1 ds-init no bin exit 1" || ko "21.1"

# --- [22] dry-run -------------------------------------------------------

echo ""
echo "[22] dry-run short-circuits all actions"
OUT=$(SNAP_DRY_RUN=true bash "$SCRIPT" --action=ds-init --kb-path="$TMP/dryX" 2>&1)
[ $? -eq 0 ] && ok "22.1 ds-init dry-run exit 0" || ko "22.1"
echo "$OUT" | jq -e '.mode == "dry-run"' >/dev/null && ok "22.2 mode" || ko "22.2"

OUT=$(SNAP_DRY_RUN=true bash "$SCRIPT" --action=ds-update --kb-path="$TMP/kb8" 2>&1)
[ $? -eq 0 ] && ok "22.3 ds-update dry-run exit 0" || ko "22.3"
echo "$OUT" | jq -e '.result.transport == "official"' >/dev/null && ok "22.4 transport in result" || ko "22.4"

OUT=$(SNAP_DRY_RUN=true bash "$SCRIPT" --action=mockup-compile --kb-path="$TMP/kb8" --scene-graph-file="$YAML" --transport=console 2>&1)
[ $? -eq 0 ] && ok "22.5 mockup-compile dry-run" || ko "22.5"
echo "$OUT" | jq -e '.result.transport == "console"' >/dev/null && ok "22.6 transport=console echoed" || ko "22.6"

OUT=$(SNAP_DRY_RUN=true bash "$SCRIPT" --action=extract-ds --kb-path="$TMP/kb8" --file-key=K --token-env=FIGMA_TOKEN 2>&1)
[ $? -eq 0 ] && ok "22.7 extract-ds dry-run (skips token check)" || ko "22.7"

OUT=$(SNAP_DRY_RUN=true bash "$SCRIPT" --action=export-shape --node-id=1:1 --output-path=/abs/x.png 2>&1)
[ $? -eq 0 ] && ok "22.8 export-shape dry-run exit 0" || ko "22.8"
echo "$OUT" | jq -e '.result.format == "png"' >/dev/null && ok "22.9 dry-run format" || ko "22.9"

# --- [23] file_key + transport propagation ------------------------------

echo ""
echo "[23] transport=official descriptor includes kb_path metadata"
mkdir -p "$TMP/kb23"
OUT=$(bash "$SCRIPT" --action=ds-update --kb-path="$TMP/kb23" 2>&1)
echo "$OUT" | jq -e --arg kb "$TMP/kb23" '.descriptor.kb_path == $kb' >/dev/null && ok "23.1 kb_path in descriptor" || ko "23.1"

# --- summary ------------------------------------------------------------

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
