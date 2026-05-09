#!/usr/bin/env bash
# Tests for skills/_shared/docs-adapter.sh

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/skills/_shared/docs-adapter.sh"

PASS=0
FAIL=0
ERRORS=()

ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

cleanup() {
  [ -n "${TMP:-}" ] && [ -d "$TMP" ] && { trash "$TMP" 2>/dev/null || rm -rf "$TMP"; }
}
trap cleanup EXIT

unset ARTYSAN_DRY_RUN ARTYSAN_PROJECT_ROOT 2>/dev/null || true

echo "=== docs-adapter.sh tests ==="

# --- arg validation -------------------------------------------------------

echo ""
echo "[1] help exit 0"
bash "$SCRIPT" --help >/dev/null 2>&1
[ $? -eq 0 ] && ok "1.1" || ko "1.1"

echo ""
echo "[2] missing --action"
bash "$SCRIPT" >/dev/null 2>&1
[ $? -eq 2 ] && ok "2.1 exit 2" || ko "2.1"

echo ""
echo "[3] bad action"
bash "$SCRIPT" --action=foo --platform=affine >/dev/null 2>&1
[ $? -eq 2 ] && ok "3.1" || ko "3.1"

echo ""
echo "[4] missing platform (no config)"
TMP=$(mktemp -d)
bash "$SCRIPT" --action=search --query=hi --project-root="$TMP" >/dev/null 2>&1
[ $? -eq 2 ] && ok "4.1" || ko "4.1"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

echo ""
echo "[5] bad platform"
bash "$SCRIPT" --action=search --query=hi --platform=confluence >/dev/null 2>&1
[ $? -eq 2 ] && ok "5.1" || ko "5.1"

# --- per-action required flags --------------------------------------------

echo ""
echo "[6] get requires --page-id"
bash "$SCRIPT" --action=get --platform=affine >/dev/null 2>&1
[ $? -eq 2 ] && ok "6.1" || ko "6.1"

echo ""
echo "[7] create requires --title"
bash "$SCRIPT" --action=create --platform=affine >/dev/null 2>&1
[ $? -eq 2 ] && ok "7.1" || ko "7.1"

echo ""
echo "[8] apply-template requires --template-name + page/parent"
bash "$SCRIPT" --action=apply-template --platform=affine >/dev/null 2>&1
[ $? -eq 2 ] && ok "8.1 missing tpl" || ko "8.1"
bash "$SCRIPT" --action=apply-template --platform=affine --template-name=x >/dev/null 2>&1
[ $? -eq 2 ] && ok "8.2 missing target" || ko "8.2"

echo ""
echo "[9] upload-blob requires existing file"
bash "$SCRIPT" --action=upload-blob --platform=affine --blob-path=/nope/missing.png >/dev/null 2>&1
rc=$?
[ $rc -eq 1 ] && ok "9.1 missing file exit 1" || ko "9.1 rc=$rc"

echo ""
echo "[10] update needs id + at least one field"
bash "$SCRIPT" --action=update --platform=affine --page-id=p1 >/dev/null 2>&1
[ $? -eq 2 ] && ok "10.1 needs body" || ko "10.1"
bash "$SCRIPT" --action=update --platform=affine --title=x >/dev/null 2>&1
[ $? -eq 2 ] && ok "10.2 needs page-id" || ko "10.2"

echo ""
echo "[11] search requires --query"
bash "$SCRIPT" --action=search --platform=affine >/dev/null 2>&1
[ $? -eq 2 ] && ok "11.1" || ko "11.1"

echo ""
echo "[12] template-vars must be valid JSON"
bash "$SCRIPT" --action=apply-template --platform=affine --template-name=x --page-id=p \
  --template-vars='{not json' >/dev/null 2>&1
[ $? -eq 2 ] && ok "12.1" || ko "12.1"

echo ""
echo "[13] --content + --content-file mutually exclusive"
TMP=$(mktemp -d); echo "body" > "$TMP/c.md"
bash "$SCRIPT" --action=update --platform=affine --page-id=p --content=x --content-file="$TMP/c.md" >/dev/null 2>&1
[ $? -eq 2 ] && ok "13.1" || ko "13.1"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

# --- MCP descriptor emission ---------------------------------------------

echo ""
echo "[14] get → MCP descriptor exit 10"
out=$(bash "$SCRIPT" --action=get --platform=affine --page-id=abc); rc=$?
[ $rc -eq 10 ]                                                                     && ok "14.1 exit 10"  || ko "14.1 rc=$rc"
[ "$(echo "$out" | jq -r '.mode')" = "mcp" ]                                       && ok "14.2 mode mcp" || ko "14.2"
[ "$(echo "$out" | jq -r '.descriptor.platform')" = "affine" ]                     && ok "14.3 platform" || ko "14.3"
[ "$(echo "$out" | jq -r '.descriptor.action')" = "get" ]                          && ok "14.4 action"   || ko "14.4"
[ "$(echo "$out" | jq -r '.descriptor.params.page_id')" = "abc" ]                  && ok "14.5 page_id"  || ko "14.5"

echo ""
echo "[15] notion create"
out=$(bash "$SCRIPT" --action=create --platform=notion --title=T --content="md" --parent-id=root); rc=$?
[ $rc -eq 10 ]                                                                     && ok "15.1 exit 10"   || ko "15.1"
[ "$(echo "$out" | jq -r '.descriptor.platform')" = "notion" ]                     && ok "15.2 platform"  || ko "15.2"
[ "$(echo "$out" | jq -r '.descriptor.params.title')" = "T" ]                      && ok "15.3 title"     || ko "15.3"
[ "$(echo "$out" | jq -r '.descriptor.params.parent_id')" = "root" ]               && ok "15.4 parent"    || ko "15.4"
[ "$(echo "$out" | jq -r '.descriptor.params.content')" = "md" ]                   && ok "15.5 content"   || ko "15.5"

echo ""
echo "[16] apply-template includes template_vars"
out=$(bash "$SCRIPT" --action=apply-template --platform=affine --template-name=prd_feature \
  --page-id=p1 --template-vars='{"feature_id":"01-foo","title":"Foo"}')
rc=$?
[ $rc -eq 10 ]                                                                            && ok "16.1 exit 10" || ko "16.1"
[ "$(echo "$out" | jq -r '.descriptor.params.template_name')" = "prd_feature" ]            && ok "16.2 tpl"     || ko "16.2"
[ "$(echo "$out" | jq -r '.descriptor.params.template_vars.feature_id')" = "01-foo" ]      && ok "16.3 vars"    || ko "16.3"
[ "$(echo "$out" | jq -r '.descriptor.params.page_id')" = "p1" ]                           && ok "16.4 page_id" || ko "16.4"

echo ""
echo "[17] search includes limit numeric"
out=$(bash "$SCRIPT" --action=search --platform=affine --query="prd" --limit=10)
[ "$(echo "$out" | jq -r '.descriptor.params.query')" = "prd" ]    && ok "17.1 query" || ko "17.1"
[ "$(echo "$out" | jq -r '.descriptor.params.limit')" = "10" ]     && ok "17.2 limit" || ko "17.2"
[ "$(echo "$out" | jq -r '.descriptor.params.limit | type')" = "number" ] && ok "17.3 numeric" || ko "17.3"

echo ""
echo "[18] upload-blob descriptor"
TMP=$(mktemp -d); echo "fake" > "$TMP/img.png"
out=$(bash "$SCRIPT" --action=upload-blob --platform=affine --blob-path="$TMP/img.png")
rc=$?
[ $rc -eq 10 ]                                                                  && ok "18.1 exit 10"   || ko "18.1"
[ "$(echo "$out" | jq -r '.descriptor.action')" = "upload-blob" ]               && ok "18.2 action"    || ko "18.2"
[ "$(echo "$out" | jq -r '.descriptor.params.blob_path')" = "$TMP/img.png" ]    && ok "18.3 path"      || ko "18.3"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

echo ""
echo "[19] content-file populates content param"
TMP=$(mktemp -d); printf '# Hello\n\nbody' > "$TMP/c.md"
out=$(bash "$SCRIPT" --action=update --platform=affine --page-id=p --content-file="$TMP/c.md")
[ "$(echo "$out" | jq -r '.descriptor.params.content')" = "$(cat "$TMP/c.md")" ] && ok "19.1 file body" || ko "19.1"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

# --- Dry-run --------------------------------------------------------------

echo ""
echo "[20] dry-run shortcut on create"
out=$(bash "$SCRIPT" --action=create --platform=affine --title=T --dry-run); rc=$?
[ $rc -eq 0 ]                                                       && ok "20.1 exit 0"  || ko "20.1"
[ "$(echo "$out" | jq -r '.mode')" = "dry-run" ]                    && ok "20.2 mode"    || ko "20.2"
[ "$(echo "$out" | jq -r '.result.title')" = "T" ]                  && ok "20.3 title"   || ko "20.3"

echo ""
echo "[21] dry-run does NOT short-circuit reads (get → exit 10)"
out=$(bash "$SCRIPT" --action=get --platform=affine --page-id=abc --dry-run); rc=$?
[ $rc -eq 10 ] && ok "21.1 read still hits MCP" || ko "21.1 rc=$rc"

echo ""
echo "[22] dry-run via env var"
out=$(ARTYSAN_DRY_RUN=true bash "$SCRIPT" --action=update --platform=notion --page-id=p --title=x); rc=$?
[ $rc -eq 0 ]                                          && ok "22.1 exit 0" || ko "22.1"
[ "$(echo "$out" | jq -r '.mode')" = "dry-run" ]       && ok "22.2 mode"   || ko "22.2"

# --- platform from config -------------------------------------------------

echo ""
echo "[23] resolves platform + workspace from config"
TMP=$(mktemp -d)
cat > "$TMP/artysan.config.json" <<'JSON'
{
  "$schema": "./skills/_shared/schemas/config.schema.json",
  "version": "1.0",
  "documentation": { "platform": "affine", "workspace": { "id": "ws-1" } }
}
JSON
out=$(bash "$SCRIPT" --action=search --query="x" --project-root="$TMP")
rc=$?
[ $rc -eq 10 ] && ok "23.1 exit 10" || ko "23.1"
[ "$(echo "$out" | jq -r '.descriptor.platform')" = "affine" ]                 && ok "23.2 platform" || ko "23.2"
[ "$(echo "$out" | jq -r '.descriptor.params.workspace_id')" = "ws-1" ]        && ok "23.3 workspace" || ko "23.3"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

echo ""
echo "[24] explicit --workspace-id overrides config"
TMP=$(mktemp -d)
cat > "$TMP/artysan.config.json" <<'JSON'
{
  "$schema": "./skills/_shared/schemas/config.schema.json",
  "version": "1.0",
  "documentation": { "platform": "affine", "workspace": { "id": "ws-1" } }
}
JSON
out=$(bash "$SCRIPT" --action=search --query="x" --project-root="$TMP" --workspace-id=ws-2)
[ "$(echo "$out" | jq -r '.descriptor.params.workspace_id')" = "ws-2" ] && ok "24.1 override" || ko "24.1"
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
