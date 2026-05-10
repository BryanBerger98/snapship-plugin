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
echo "[15] export-page defaults from config"
TMP=$(mktemp -d)
cat > "$TMP/snapship.config.json" <<'JSON'
{
  "$schema": "./skills/_shared/schemas/config.schema.json",
  "version": "1.0",
  "wireframes": { "platform":"frame0", "export_format":"svg", "export_scale":3 }
}
JSON
out=$(bash "$SCRIPT" --action=export-page --page-id=p --output-path=/tmp/o --project-root="$TMP")
[ "$(echo "$out" | jq -r '.descriptor.params.format')" = "svg" ]            && ok "15.1 fmt"   || ko "15.1"
[ "$(echo "$out" | jq -r '.descriptor.params.scale')" = "3" ]               && ok "15.2 scale" || ko "15.2"
[ "$(echo "$out" | jq -r '.descriptor.params.scale | type')" = "number" ]   && ok "15.3 numeric" || ko "15.3"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

echo ""
echo "[16] flag overrides config"
TMP=$(mktemp -d)
cat > "$TMP/snapship.config.json" <<'JSON'
{ "$schema":"./skills/_shared/schemas/config.schema.json","version":"1.0",
  "wireframes":{ "platform":"frame0","export_format":"svg","export_scale":3 } }
JSON
out=$(bash "$SCRIPT" --action=export-page --page-id=p --output-path=/tmp/o \
  --format=png --scale=1 --project-root="$TMP")
[ "$(echo "$out" | jq -r '.descriptor.params.format')" = "png" ] && ok "16.1 fmt override" || ko "16.1"
[ "$(echo "$out" | jq -r '.descriptor.params.scale')"  = "1"   ] && ok "16.2 scale override" || ko "16.2"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

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
