#!/usr/bin/env bash
# Tests for skills/_shared/penpot-helper.sh

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/skills/_shared/penpot-helper.sh"

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

echo "=== penpot-helper.sh tests ==="

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

bash "$SCRIPT" --action=export-png --shape-id=s --output-path=relative/x.png >/dev/null 2>&1
[ $? -eq 2 ] && ok "4.13 export-png rejects relative path" || ko "4.13"

bash "$SCRIPT" --action=export-png --shape-id=s --output-path=/tmp/x.png --format=jpeg >/dev/null 2>&1
[ $? -eq 2 ] && ok "4.14 export-png rejects jpeg format" || ko "4.14"

bash "$SCRIPT" --action=export-png --shape-id=s --output-path=/tmp/x.png --format=pdf >/dev/null 2>&1
[ $? -eq 2 ] && ok "4.15 export-png rejects pdf format" || ko "4.15"

# --- MCP descriptor shape -------------------------------------------------

echo ""
echo "[5] create-page emits MCP descriptor (execute_code tool)"
OUT=$(bash "$SCRIPT" --action=create-page --title='Sign Up Empty' 2>&1)
RC=$?
[ "$RC" -eq 10 ] && ok "5.1 exit 10" || ko "5.1 exit=$RC"
echo "$OUT" | jq -e '.descriptor.platform == "penpot"' >/dev/null && ok "5.2 platform=penpot" || ko "5.2"
echo "$OUT" | jq -e '.descriptor.action == "create-page"' >/dev/null && ok "5.3 action" || ko "5.3"
echo "$OUT" | jq -e '.descriptor.tool == "execute_code"' >/dev/null && ok "5.4 tool=execute_code" || ko "5.4"
echo "$OUT" | jq -e '.descriptor.params.code | contains("penpot.createPage()")' >/dev/null && ok "5.5 JS includes createPage" || ko "5.5"
echo "$OUT" | jq -e '.descriptor.params.code | contains("\"Sign Up Empty\"")' >/dev/null && ok "5.6 JS embeds title" || ko "5.6"

echo ""
echo "[6] export-png emits export_shape descriptor"
OUT=$(bash "$SCRIPT" --action=export-png --shape-id=sel-id --output-path=/abs/path.png 2>&1)
RC=$?
[ "$RC" -eq 10 ] && ok "6.1 exit 10" || ko "6.1 exit=$RC"
echo "$OUT" | jq -e '.descriptor.tool == "export_shape"' >/dev/null && ok "6.2 tool=export_shape" || ko "6.2"
echo "$OUT" | jq -e '.descriptor.params.shapeId == "sel-id"' >/dev/null && ok "6.3 shapeId" || ko "6.3"
echo "$OUT" | jq -e '.descriptor.params.format == "png"' >/dev/null && ok "6.4 format" || ko "6.4"
echo "$OUT" | jq -e '.descriptor.params.filePath == "/abs/path.png"' >/dev/null && ok "6.5 filePath" || ko "6.5"

echo ""
echo "[7] export-png with --page-id falls back as shapeId"
OUT=$(bash "$SCRIPT" --action=export-png --page-id=page-uuid --output-path=/abs/p.png 2>&1)
echo "$OUT" | jq -e '.descriptor.params.shapeId == "page-uuid"' >/dev/null && ok "7.1 page-id mapped to shapeId" || ko "7.1"

echo ""
echo "[8] export-png with svg format"
OUT=$(bash "$SCRIPT" --action=export-png --shape-id=s --output-path=/abs/x.svg --format=svg 2>&1)
[ $? -eq 10 ] && ok "8.1 svg accepted" || ko "8.1"
echo "$OUT" | jq -e '.descriptor.params.format == "svg"' >/dev/null && ok "8.2 format=svg" || ko "8.2"

# --- add-shapes JS construction -------------------------------------------

echo ""
echo "[9] add-shapes JS includes page lookup + shape loop"
OUT=$(bash "$SCRIPT" --action=add-shapes --page-id=page-x \
  --shapes='[{"type":"text","name":"Title","x":40,"y":40,"width":200,"height":40,"text":"Hi","fill":"#000"},{"type":"rect","name":"Bg","x":0,"y":0,"width":300,"height":200}]' 2>&1)
RC=$?
[ "$RC" -eq 10 ] && ok "9.1 exit 10" || ko "9.1 rc=$RC"
JS=$(echo "$OUT" | jq -r '.descriptor.params.code')
echo "$JS" | grep -q 'getPageById("page-x")' && ok "9.2 getPageById" || ko "9.2"
echo "$JS" | grep -q 'penpot.openPage(page)' && ok "9.3 openPage" || ko "9.3"
echo "$JS" | grep -q 'penpot.createText' && ok "9.4 createText" || ko "9.4"
echo "$JS" | grep -q 'penpot.createRectangle' && ok "9.5 createRectangle" || ko "9.5"
echo "$JS" | grep -q '"Title"' && ok "9.6 shape name embedded" || ko "9.6"

echo ""
echo "[10] add-shapes from --shapes-file"
TMP=$(mktemp -d)
SF="$TMP/shapes.json"
cat > "$SF" <<'EOF'
[{"type":"ellipse","name":"Avatar","x":10,"y":10,"width":40,"height":40,"fill":"#ddd"}]
EOF
OUT=$(bash "$SCRIPT" --action=add-shapes --page-id=p --shapes-file="$SF" 2>&1)
RC=$?
[ "$RC" -eq 10 ] && ok "10.1 file load ok" || ko "10.1 rc=$RC"
echo "$OUT" | jq -e '.descriptor.params.code | contains("createEllipse")' >/dev/null && ok "10.2 ellipse path" || ko "10.2"

bash "$SCRIPT" --action=add-shapes --page-id=p --shapes-file="$TMP/missing.json" >/dev/null 2>&1
[ $? -eq 1 ] && ok "10.3 missing file exit 1" || ko "10.3"

# --- get-page / update-page / delete-page / list-pages --------------------

echo ""
echo "[11] read/update/delete actions"
OUT=$(bash "$SCRIPT" --action=get-page --page-id=abc 2>&1)
[ $? -eq 10 ] && ok "11.1 get-page exit 10" || ko "11.1"
echo "$OUT" | jq -e '.descriptor.params.code | contains("getPageById")' >/dev/null && ok "11.2 get-page JS" || ko "11.2"

OUT=$(bash "$SCRIPT" --action=update-page --page-id=abc --title='New' 2>&1)
[ $? -eq 10 ] && ok "11.3 update-page exit 10" || ko "11.3"
echo "$OUT" | jq -e '.descriptor.params.code | contains("\"New\"")' >/dev/null && ok "11.4 update-page title embed" || ko "11.4"

OUT=$(bash "$SCRIPT" --action=delete-page --page-id=abc 2>&1)
[ $? -eq 10 ] && ok "11.5 delete-page exit 10" || ko "11.5"
echo "$OUT" | jq -e '.descriptor.params.code | contains("removePage")' >/dev/null && ok "11.6 removePage" || ko "11.6"

OUT=$(bash "$SCRIPT" --action=list-pages --query='home' --limit=5 2>&1)
[ $? -eq 10 ] && ok "11.7 list-pages exit 10" || ko "11.7"
echo "$OUT" | jq -e '.descriptor.params.code | contains("getPages()")' >/dev/null && ok "11.8 getPages" || ko "11.8"
echo "$OUT" | jq -e '.descriptor.params.code | contains(".slice(0, 5)")' >/dev/null && ok "11.9 limit applied" || ko "11.9"

# --- dry-run --------------------------------------------------------------

echo ""
echo "[12] dry-run short-circuits writes"
OUT=$(SNAP_DRY_RUN=true bash "$SCRIPT" --action=create-page --title=DryX 2>&1)
[ $? -eq 0 ] && ok "12.1 dry-run create-page exit 0" || ko "12.1"
echo "$OUT" | jq -e '.mode == "dry-run"' >/dev/null && ok "12.2 mode=dry-run" || ko "12.2"
echo "$OUT" | jq -e '.platform == "penpot"' >/dev/null && ok "12.3 platform=penpot" || ko "12.3"

OUT=$(bash "$SCRIPT" --dry-run --action=export-png --shape-id=s --output-path=/abs/x.png 2>&1)
[ $? -eq 0 ] && ok "12.4 dry-run export-png exit 0" || ko "12.4"
echo "$OUT" | jq -e '.result.written == false' >/dev/null && ok "12.5 written=false" || ko "12.5"

OUT=$(SNAP_DRY_RUN=true bash "$SCRIPT" --action=add-shapes --page-id=p --shapes='[]' 2>&1)
[ $? -eq 0 ] && ok "12.6 dry-run add-shapes" || ko "12.6"

# --- read-only actions don't dry-run (no write to mock) ------------------

echo ""
echo "[13] dry-run does NOT short-circuit read actions"
OUT=$(SNAP_DRY_RUN=true bash "$SCRIPT" --action=get-page --page-id=p 2>&1)
[ $? -eq 10 ] && ok "13.1 get-page still emits descriptor" || ko "13.1"

OUT=$(SNAP_DRY_RUN=true bash "$SCRIPT" --action=list-pages --query=x 2>&1)
[ $? -eq 10 ] && ok "13.2 list-pages still emits descriptor" || ko "13.2"

# --- config-driven export_format default ---------------------------------

echo ""
echo "[14] export_format reads config when unset"
CFG_DIR=$(mktemp -d)
cat > "$CFG_DIR/snapship.config.json" <<'EOF'
{"version":"1.0","wireframes":{"platform":"penpot","export_format":"svg"}}
EOF
OUT=$(bash "$SCRIPT" --project-root="$CFG_DIR" --action=export-png --shape-id=s --output-path=/abs/x.svg 2>&1)
RC=$?
[ "$RC" -eq 10 ] && ok "14.1 config format ok" || ko "14.1 rc=$RC"
echo "$OUT" | jq -e '.descriptor.params.format == "svg"' >/dev/null && ok "14.2 format from config" || ko "14.2"
trash "$CFG_DIR" 2>/dev/null || rm -rf "$CFG_DIR"

# --- get-current-file preflight ------------------------------------------

echo ""
echo "[15] get-current-file no-arg preflight"
OUT=$(bash "$SCRIPT" --action=get-current-file 2>&1)
RC=$?
[ "$RC" -eq 10 ] && ok "15.1 exit 10" || ko "15.1 rc=$RC"
echo "$OUT" | jq -e '.descriptor.tool == "execute_code"' >/dev/null && ok "15.2 tool=execute_code" || ko "15.2"
echo "$OUT" | jq -e '.descriptor.action == "get-current-file"' >/dev/null && ok "15.3 action" || ko "15.3"
echo "$OUT" | jq -e '.descriptor.params.code | contains("penpot.currentFile")' >/dev/null && ok "15.4 currentFile in JS" || ko "15.4"
echo "$OUT" | jq -e '.descriptor.params.code | contains("({id: f.id, name: f.name})")' >/dev/null && ok "15.5 returns {id,name}" || ko "15.5"

echo ""
echo "[16] get-current-file unaffected by dry-run (read action)"
OUT=$(SNAP_DRY_RUN=true bash "$SCRIPT" --action=get-current-file 2>&1)
[ $? -eq 10 ] && ok "16.1 still emits descriptor" || ko "16.1"

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
