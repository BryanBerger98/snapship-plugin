#!/usr/bin/env bash
# Tests for skills/_shared/frame0-helper.sh

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/skills/_shared/frame0-helper.sh"

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

echo "=== frame0-helper.sh tests ==="

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
echo "[4] bad format/scale"
bash "$SCRIPT" --action=create-page --title=x --format=bmp >/dev/null 2>&1
[ $? -eq 2 ] && ok "4.1 bad format" || ko "4.1"
bash "$SCRIPT" --action=create-page --title=x --scale=4   >/dev/null 2>&1
[ $? -eq 2 ] && ok "4.2 bad scale" || ko "4.2"

# --- per-action validation -----------------------------------------------

echo ""
echo "[5] create-page requires --title"
bash "$SCRIPT" --action=create-page >/dev/null 2>&1
[ $? -eq 2 ] && ok "5.1" || ko "5.1"

echo ""
echo "[6] get-page / delete-page require --page-id"
bash "$SCRIPT" --action=get-page    >/dev/null 2>&1
[ $? -eq 2 ] && ok "6.1 get" || ko "6.1"
bash "$SCRIPT" --action=delete-page >/dev/null 2>&1
[ $? -eq 2 ] && ok "6.2 delete" || ko "6.2"

echo ""
echo "[7] update-page requires --page-id and --title"
bash "$SCRIPT" --action=update-page --page-id=p >/dev/null 2>&1
[ $? -eq 2 ] && ok "7.1 needs title" || ko "7.1"
bash "$SCRIPT" --action=update-page --title=t   >/dev/null 2>&1
[ $? -eq 2 ] && ok "7.2 needs id"    || ko "7.2"

echo ""
echo "[8] list-pages requires --query"
bash "$SCRIPT" --action=list-pages >/dev/null 2>&1
[ $? -eq 2 ] && ok "8.1" || ko "8.1"

echo ""
echo "[9] add-shapes requires page-id + shapes"
bash "$SCRIPT" --action=add-shapes >/dev/null 2>&1
[ $? -eq 2 ] && ok "9.1 needs id"    || ko "9.1"
bash "$SCRIPT" --action=add-shapes --page-id=p >/dev/null 2>&1
[ $? -eq 2 ] && ok "9.2 needs shapes" || ko "9.2"

echo ""
echo "[10] add-shapes rejects non-array JSON"
bash "$SCRIPT" --action=add-shapes --page-id=p --shapes='{"x":1}' >/dev/null 2>&1
[ $? -eq 2 ] && ok "10.1 not array" || ko "10.1"
bash "$SCRIPT" --action=add-shapes --page-id=p --shapes='not json' >/dev/null 2>&1
[ $? -eq 2 ] && ok "10.2 invalid json" || ko "10.2"

echo ""
echo "[11] add-shapes accepts file"
TMP=$(mktemp -d); echo '[{"type":"rect"}]' > "$TMP/s.json"
out=$(bash "$SCRIPT" --action=add-shapes --page-id=p --shapes-file="$TMP/s.json")
rc=$?
[ $rc -eq 10 ] && ok "11.1 exit 10" || ko "11.1"
[ "$(echo "$out" | jq -r '.descriptor.params.shapes[0].type')" = "rect" ] && ok "11.2 shapes loaded" || ko "11.2"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

echo ""
echo "[12] add-shapes mutex shapes/shapes-file"
TMP=$(mktemp -d); echo '[]' > "$TMP/s.json"
bash "$SCRIPT" --action=add-shapes --page-id=p --shapes='[]' --shapes-file="$TMP/s.json" >/dev/null 2>&1
[ $? -eq 2 ] && ok "12.1 mutex" || ko "12.1"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

echo ""
echo "[13] export-page requires page-id and output-path"
bash "$SCRIPT" --action=export-page --page-id=p >/dev/null 2>&1
[ $? -eq 2 ] && ok "13.1 needs out" || ko "13.1"
bash "$SCRIPT" --action=export-page --output-path=/tmp/x.png >/dev/null 2>&1
[ $? -eq 2 ] && ok "13.2 needs id"  || ko "13.2"

# --- MCP descriptors ------------------------------------------------------

echo ""
echo "[14] create-page descriptor"
out=$(bash "$SCRIPT" --action=create-page --title="Home" --parent-id=root)
rc=$?
[ $rc -eq 10 ]                                                              && ok "14.1 exit 10"  || ko "14.1"
[ "$(echo "$out" | jq -r '.descriptor.platform')" = "frame0" ]              && ok "14.2 platform" || ko "14.2"
[ "$(echo "$out" | jq -r '.descriptor.action')" = "create-page" ]           && ok "14.3 action"   || ko "14.3"
[ "$(echo "$out" | jq -r '.descriptor.params.title')" = "Home" ]            && ok "14.4 title"    || ko "14.4"
[ "$(echo "$out" | jq -r '.descriptor.params.parent_id')" = "root" ]        && ok "14.5 parent"   || ko "14.5"

echo ""
echo "[15] export-page internal defaults (helper context-agnostic depuis v0.5)"
out=$(bash "$SCRIPT" --action=export-page --page-id=p --output-path=/tmp/o)
[ "$(echo "$out" | jq -r '.descriptor.params.format')" = "png" ]            && ok "15.1 fmt defaults png"   || ko "15.1"
[ "$(echo "$out" | jq -r '.descriptor.params.scale')" = "2" ]               && ok "15.2 scale defaults 2"   || ko "15.2"
[ "$(echo "$out" | jq -r '.descriptor.params.scale | type')" = "number" ]   && ok "15.3 numeric"            || ko "15.3"

echo ""
echo "[16] explicit --format/--scale flags"
out=$(bash "$SCRIPT" --action=export-page --page-id=p --output-path=/tmp/o \
  --format=svg --scale=3)
[ "$(echo "$out" | jq -r '.descriptor.params.format')" = "svg" ] && ok "16.1 fmt explicit" || ko "16.1"
[ "$(echo "$out" | jq -r '.descriptor.params.scale')"  = "3"   ] && ok "16.2 scale explicit" || ko "16.2"

echo ""
echo "[17] list-pages limit numeric"
out=$(bash "$SCRIPT" --action=list-pages --query="login" --limit=5)
[ "$(echo "$out" | jq -r '.descriptor.params.query')" = "login" ]        && ok "17.1 query" || ko "17.1"
[ "$(echo "$out" | jq -r '.descriptor.params.limit | type')" = "number" ] && ok "17.2 numeric" || ko "17.2"

echo ""
echo "[18] add-shapes preserves array"
out=$(bash "$SCRIPT" --action=add-shapes --page-id=p \
  --shapes='[{"type":"rect","w":100},{"type":"text","content":"hi"}]')
[ "$(echo "$out" | jq -r '.descriptor.params.shapes | length')" = "2" ]  && ok "18.1 len"   || ko "18.1"
[ "$(echo "$out" | jq -r '.descriptor.params.shapes[1].type')" = "text" ] && ok "18.2 type"  || ko "18.2"

echo ""
echo "[19] delete-page descriptor"
out=$(bash "$SCRIPT" --action=delete-page --page-id=zz)
[ "$(echo "$out" | jq -r '.descriptor.action')" = "delete-page" ]     && ok "19.1 action" || ko "19.1"
[ "$(echo "$out" | jq -r '.descriptor.params.page_id')" = "zz" ]      && ok "19.2 id"     || ko "19.2"

# --- Dry-run --------------------------------------------------------------

echo ""
echo "[20] dry-run create"
out=$(bash "$SCRIPT" --action=create-page --title=T --dry-run); rc=$?
[ $rc -eq 0 ]                                          && ok "20.1 exit 0" || ko "20.1"
[ "$(echo "$out" | jq -r '.mode')" = "dry-run" ]       && ok "20.2 mode"   || ko "20.2"
[ "$(echo "$out" | jq -r '.platform')" = "frame0" ]    && ok "20.3 plat"   || ko "20.3"

echo ""
echo "[21] dry-run export includes format/scale"
out=$(bash "$SCRIPT" --action=export-page --page-id=p --output-path=/tmp/o --dry-run)
[ "$(echo "$out" | jq -r '.result.format')" = "png" ]   && ok "21.1 fmt"   || ko "21.1"
[ "$(echo "$out" | jq -r '.result.scale')"  = "2"   ]   && ok "21.2 scale" || ko "21.2"

echo ""
echo "[22] dry-run does NOT short-circuit reads"
out=$(bash "$SCRIPT" --action=get-page --page-id=p --dry-run); rc=$?
[ $rc -eq 10 ] && ok "22.1 read still MCP" || ko "22.1 rc=$rc"

echo ""
echo "[23] dry-run via env"
out=$(SNAP_DRY_RUN=true bash "$SCRIPT" --action=delete-page --page-id=p)
[ "$(echo "$out" | jq -r '.mode')" = "dry-run" ] && ok "23.1" || ko "23.1"

# --- save-export ----------------------------------------------------------
# 1×1 transparent PNG, base64-encoded. Decodes to 67 bytes.
PNG_B64="iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkAAIAAAoAAv/lxKUAAAAASUVORK5CYII="

echo ""
echo "[24] save-export requires --output-path and a payload source"
bash "$SCRIPT" --action=save-export                                >/dev/null 2>&1
[ $? -eq 2 ] && ok "24.1 needs out" || ko "24.1"
bash "$SCRIPT" --action=save-export --output-path=/tmp/x.png       >/dev/null 2>&1
[ $? -eq 2 ] && ok "24.2 needs payload" || ko "24.2"
bash "$SCRIPT" --action=save-export --base64-data="$PNG_B64"       >/dev/null 2>&1
[ $? -eq 2 ] && ok "24.3 needs out (with data)" || ko "24.3"

echo ""
echo "[25] save-export rejects multiple payload sources"
TMP=$(mktemp -d); echo "$PNG_B64" > "$TMP/p.b64"
bash "$SCRIPT" --action=save-export --output-path="$TMP/x.png" \
  --base64-data="$PNG_B64" --base64-file="$TMP/p.b64" >/dev/null 2>&1
[ $? -eq 2 ] && ok "25.1 mutex data+file" || ko "25.1"
bash "$SCRIPT" --action=save-export --output-path="$TMP/x.png" \
  --base64-data="$PNG_B64" --base64-stdin </dev/null >/dev/null 2>&1
[ $? -eq 2 ] && ok "25.2 mutex data+stdin" || ko "25.2"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

echo ""
echo "[26] save-export base64-file not found"
out=$(bash "$SCRIPT" --action=save-export --output-path=/tmp/x.png \
        --base64-file=/no/such/file.b64 2>&1)
rc=$?
[ $rc -eq 1 ] && ok "26.1 exit 1" || ko "26.1 rc=$rc"

echo ""
echo "[27] save-export decodes base64 → PNG (via --base64-data)"
TMP=$(mktemp -d)
TARGET="$TMP/.snap/wireframes/01-auth/01-auth-signup-empty.png"
out=$(bash "$SCRIPT" --action=save-export --output-path="$TARGET" \
        --base64-data="$PNG_B64")
rc=$?
[ $rc -eq 0 ] && ok "27.1 exit 0" || ko "27.1 rc=$rc"
[ "$(echo "$out" | jq -r '.ok')" = "true" ] && ok "27.2 ok=true" || ko "27.2"
[ "$(echo "$out" | jq -r '.mode')" = "local" ] && ok "27.3 mode=local" || ko "27.3"
[ -f "$TARGET" ] && ok "27.4 target exists" || ko "27.4"
# PNG signature: 89 50 4E 47 0D 0A 1A 0A
sig=$(head -c 8 "$TARGET" | od -An -tx1 | tr -d ' \n')
[ "$sig" = "89504e470d0a1a0a" ] && ok "27.5 PNG signature" || ko "27.5 got '$sig'"
[ "$(echo "$out" | jq -r '.result.bytes')" = "$(wc -c < "$TARGET" | tr -d ' ')" ] && ok "27.6 bytes match" || ko "27.6"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

echo ""
echo "[28] save-export from --base64-file"
TMP=$(mktemp -d); echo "$PNG_B64" > "$TMP/p.b64"
TARGET="$TMP/out.png"
out=$(bash "$SCRIPT" --action=save-export --output-path="$TARGET" --base64-file="$TMP/p.b64")
[ $? -eq 0 ] && ok "28.1 exit 0" || ko "28.1"
[ -f "$TARGET" ] && ok "28.2 file written" || ko "28.2"
sig=$(head -c 8 "$TARGET" | od -An -tx1 | tr -d ' \n')
[ "$sig" = "89504e470d0a1a0a" ] && ok "28.3 PNG signature" || ko "28.3"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

echo ""
echo "[29] save-export from --base64-stdin (and strips data URI prefix)"
TMP=$(mktemp -d)
TARGET="$TMP/uri.png"
out=$(printf 'data:image/png;base64,%s' "$PNG_B64" \
        | bash "$SCRIPT" --action=save-export --output-path="$TARGET" --base64-stdin)
[ $? -eq 0 ] && ok "29.1 exit 0" || ko "29.1"
sig=$(head -c 8 "$TARGET" | od -An -tx1 | tr -d ' \n')
[ "$sig" = "89504e470d0a1a0a" ] && ok "29.2 PNG signature after prefix strip" || ko "29.2"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

echo ""
echo "[30] save-export dry-run does not write the file"
TMP=$(mktemp -d)
TARGET="$TMP/out/dry.png"
out=$(bash "$SCRIPT" --action=save-export --output-path="$TARGET" \
        --base64-data="$PNG_B64" --dry-run)
rc=$?
[ $rc -eq 0 ] && ok "30.1 exit 0" || ko "30.1"
[ ! -f "$TARGET" ] && ok "30.2 target untouched" || ko "30.2"
[ "$(echo "$out" | jq -r '.result.written')" = "false" ] && ok "30.3 written=false" || ko "30.3"
[ "$(echo "$out" | jq -r '.result.base64_chars | type')" = "number" ] && ok "30.4 chars numeric" || ko "30.4"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

echo ""
echo "[31] save-export never emits MCP descriptor"
TMP=$(mktemp -d)
out=$(bash "$SCRIPT" --action=save-export --output-path="$TMP/x.png" --base64-data="$PNG_B64")
desc=$(echo "$out" | jq -r '.descriptor // empty')
[ -z "$desc" ]                                       && ok "31.1 no descriptor" || ko "31.1"
[ "$(echo "$out" | jq -r '.mode')" = "local" ]       && ok "31.2 mode=local"    || ko "31.2"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

echo ""
echo "[32] save-export rejects empty payload"
out=$(bash "$SCRIPT" --action=save-export --output-path=/tmp/empty.png --base64-data="   " 2>&1)
[ $? -eq 1 ] && ok "32.1 exit 1" || ko "32.1"

echo ""
echo "[33] save-export rejects invalid base64"
TMP=$(mktemp -d)
out=$(bash "$SCRIPT" --action=save-export --output-path="$TMP/bad.png" \
        --base64-data="!!!not-base64!!!" 2>&1)
rc=$?
# Some `base64` implementations are lenient and decode garbage to garbage without
# failing. Accept either: hard fail (exit 1) OR a written file that does not
# carry a PNG signature.
if [ $rc -eq 1 ]; then
  ok "33.1 strict reject"
else
  if [ -f "$TMP/bad.png" ]; then
    sig=$(head -c 8 "$TMP/bad.png" | od -An -tx1 | tr -d ' \n')
    [ "$sig" != "89504e470d0a1a0a" ] && ok "33.1 lenient (not PNG)" || ko "33.1 fake PNG produced"
  else
    ko "33.1 unexpected rc=$rc with no file"
  fi
fi
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

# --- export-png (HTTP API bypass) ----------------------------------------

echo ""
echo "[34] export-png requires --page-id and --output-path"
bash "$SCRIPT" --action=export-png                                  >/dev/null 2>&1
[ $? -eq 2 ] && ok "34.1 needs page-id" || ko "34.1"
bash "$SCRIPT" --action=export-png --page-id=p                      >/dev/null 2>&1
[ $? -eq 2 ] && ok "34.2 needs out" || ko "34.2"
bash "$SCRIPT" --action=export-png --output-path=/tmp/x.png         >/dev/null 2>&1
[ $? -eq 2 ] && ok "34.3 needs page-id" || ko "34.3"

echo ""
echo "[35] export-png format enum: png|jpeg|webp only"
bash "$SCRIPT" --action=export-png --page-id=p --output-path=/tmp/x.png --format=svg >/dev/null 2>&1
[ $? -eq 2 ] && ok "35.1 rejects svg" || ko "35.1"
bash "$SCRIPT" --action=export-png --page-id=p --output-path=/tmp/x.png --format=pdf >/dev/null 2>&1
[ $? -eq 2 ] && ok "35.2 rejects pdf" || ko "35.2"
bash "$SCRIPT" --action=export-png --page-id=p --output-path=/tmp/x.png --format=jpeg --dry-run >/dev/null 2>&1
[ $? -eq 0 ] && ok "35.3 accepts jpeg" || ko "35.3"
bash "$SCRIPT" --action=export-png --page-id=p --output-path=/tmp/x.png --format=webp --dry-run >/dev/null 2>&1
[ $? -eq 0 ] && ok "35.4 accepts webp" || ko "35.4"

echo ""
echo "[36] export-png validates --api-port"
bash "$SCRIPT" --action=export-png --page-id=p --output-path=/tmp/x.png --api-port=abc >/dev/null 2>&1
[ $? -eq 2 ] && ok "36.1 non-numeric" || ko "36.1"
bash "$SCRIPT" --action=export-png --page-id=p --output-path=/tmp/x.png --api-port=70000 >/dev/null 2>&1
[ $? -eq 2 ] && ok "36.2 out of range" || ko "36.2"

echo ""
echo "[37] export-png dry-run does not call HTTP API"
out=$(bash "$SCRIPT" --action=export-png --page-id=p123 --output-path=/tmp/dry.png \
        --api-port=58320 --dry-run)
rc=$?
[ $rc -eq 0 ] && ok "37.1 exit 0" || ko "37.1"
[ "$(echo "$out" | jq -r '.mode')" = "dry-run" ] && ok "37.2 mode" || ko "37.2"
[ "$(echo "$out" | jq -r '.result.api_base')" = "http://localhost:58320" ] && ok "37.3 api_base" || ko "37.3"
[ "$(echo "$out" | jq -r '.result.mime')" = "image/png" ] && ok "37.4 mime" || ko "37.4"
[ ! -f /tmp/dry.png ] && ok "37.5 no file written" || ko "37.5"

echo ""
echo "[38] export-png mock success → PNG written"
TMP=$(mktemp -d)
PNG_B64="iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkAAIAAAoAAv/lxKUAAAAASUVORK5CYII="
echo "{\"success\":true,\"data\":\"$PNG_B64\"}" > "$TMP/resp.json"
TARGET="$TMP/wf/feat-screen-state.png"
out=$(SNAP_FRAME0_MOCK_RESPONSE_FILE="$TMP/resp.json" \
  bash "$SCRIPT" --action=export-png --page-id=p1 --output-path="$TARGET")
rc=$?
[ $rc -eq 0 ] && ok "38.1 exit 0" || ko "38.1 rc=$rc"
[ "$(echo "$out" | jq -r '.ok')" = "true" ] && ok "38.2 ok=true" || ko "38.2"
[ "$(echo "$out" | jq -r '.mode')" = "local" ] && ok "38.3 mode=local" || ko "38.3"
[ -f "$TARGET" ] && ok "38.4 target exists" || ko "38.4"
sig=$(head -c 8 "$TARGET" | od -An -tx1 | tr -d ' \n')
[ "$sig" = "89504e470d0a1a0a" ] && ok "38.5 PNG signature" || ko "38.5"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

echo ""
echo "[39] export-png mock API error → exit 1"
TMP=$(mktemp -d)
echo '{"success":false,"error":"page not found"}' > "$TMP/resp.json"
out=$(SNAP_FRAME0_MOCK_RESPONSE_FILE="$TMP/resp.json" \
  bash "$SCRIPT" --action=export-png --page-id=bad --output-path="$TMP/x.png" 2>&1)
rc=$?
[ $rc -eq 1 ] && ok "39.1 exit 1" || ko "39.1 rc=$rc"
echo "$out" | grep -q "page not found" && ok "39.2 surfaces API error" || ko "39.2"
[ ! -f "$TMP/x.png" ] && ok "39.3 no file written" || ko "39.3"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

echo ""
echo "[40] export-png mock missing .data → exit 1"
TMP=$(mktemp -d)
echo '{"success":true}' > "$TMP/resp.json"
SNAP_FRAME0_MOCK_RESPONSE_FILE="$TMP/resp.json" \
  bash "$SCRIPT" --action=export-png --page-id=p --output-path="$TMP/x.png" >/dev/null 2>&1
[ $? -eq 1 ] && ok "40.1 exit 1" || ko "40.1"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

echo ""
echo "[41] export-png mock malformed JSON → exit 1"
TMP=$(mktemp -d)
echo 'not json' > "$TMP/resp.json"
SNAP_FRAME0_MOCK_RESPONSE_FILE="$TMP/resp.json" \
  bash "$SCRIPT" --action=export-png --page-id=p --output-path="$TMP/x.png" >/dev/null 2>&1
[ $? -eq 1 ] && ok "41.1 exit 1" || ko "41.1"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

echo ""
echo "[42] export-png live HTTP fails when Frame0 not running (port 1)"
out=$(bash "$SCRIPT" --action=export-png --page-id=p --output-path=/tmp/nx.png \
        --api-port=1 2>&1)
rc=$?
[ $rc -eq 1 ] && ok "42.1 exit 1" || ko "42.1 rc=$rc"
echo "$out" | grep -q "HTTP call" && ok "42.2 surfaces HTTP error" || ko "42.2"

echo ""
echo "[43] export-png --api-port flag (helper context-agnostic — pas de lecture config)"
TMP=$(mktemp -d)
out=$(bash "$SCRIPT" --action=export-png --page-id=p --output-path="$TMP/x.png" \
        --api-port=59999 --dry-run)
[ "$(echo "$out" | jq -r '.result.api_base')" = "http://localhost:59999" ] \
  && ok "43.1 port from flag" || ko "43.1"

echo ""
echo "[43b] export-png defaults to port 58320 sans --api-port (config ignorée)"
cat > "$TMP/snapship.config.json" <<'JSON'
{ "$schema":"./skills/_shared/schemas/config.schema.json","version":"1.0",
  "wireframes":{ "platform":"frame0","frame0":{"api_port":59999} } }
JSON
out=$(bash "$SCRIPT" --action=export-png --page-id=p --output-path="$TMP/x.png" \
        --project-root="$TMP" --dry-run)
[ "$(echo "$out" | jq -r '.result.api_base')" = "http://localhost:58320" ] \
  && ok "43b.1 helper ignore config, default 58320" || ko "43b.1"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

echo ""
echo "[44] export-png never emits MCP descriptor"
TMP=$(mktemp -d)
echo "{\"success\":true,\"data\":\"$PNG_B64\"}" > "$TMP/resp.json"
out=$(SNAP_FRAME0_MOCK_RESPONSE_FILE="$TMP/resp.json" \
  bash "$SCRIPT" --action=export-png --page-id=p --output-path="$TMP/x.png")
desc=$(echo "$out" | jq -r '.descriptor // empty')
[ -z "$desc" ] && ok "44.1 no descriptor" || ko "44.1"
[ "$(echo "$out" | jq -r '.mode')" = "local" ] && ok "44.2 mode=local" || ko "44.2"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

unset TMP

echo ""
echo "=== Summary ==="
echo "Passed: ${PASS}"
echo "Failed: ${FAIL}"

if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "Errors:"
  printf '  - %s\n' "${ERRORS[@]}"
  exit 1
fi
