#!/usr/bin/env bash
# Tests for skills/_shared/check-mcp-required.sh

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/skills/_shared/check-mcp-required.sh"

PASS=0
FAIL=0
ERRORS=()

ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

cleanup() {
  [ -n "${TMP:-}" ] && [ -d "$TMP" ] && { trash "$TMP" 2>/dev/null || rm -rf "$TMP"; }
}
trap cleanup EXIT

# Isolate from any inherited env
unset SNAP_MCP_AVAILABLE 2>/dev/null || true

echo "=== check-mcp-required.sh tests ==="

# 1. All required present, no optional
echo ""
echo "[1] all required present"
out=$(bash "$SCRIPT" --required=a,b --available=a,b,c --no-config)
rc=$?
[ $rc -eq 0 ] && ok "1.1 exit 0" || ko "1.1 exit $rc"
[ "$(echo "$out" | jq -r '.ok')" = "true" ] && ok "1.2 ok=true" || ko "1.2"
[ "$(echo "$out" | jq -r '.missing_required | length')" = "0" ] && ok "1.3 no missing" || ko "1.3"

# 2. Missing required → fail-fast
echo ""
echo "[2] missing required"
out=$(bash "$SCRIPT" --required=a,b,c --available=a --no-config); rc=$?
[ $rc -eq 1 ] && ok "2.1 exit 1" || ko "2.1 exit $rc"
[ "$(echo "$out" | jq -r '.ok')" = "false" ] && ok "2.2 ok=false" || ko "2.2"
[ "$(echo "$out" | jq -r '.missing_required | sort | join(",")')" = "b,c" ] && ok "2.3 missing list" || ko "2.3 got $(echo "$out" | jq -r '.missing_required | join(",")')"

# 3. Missing optional → still ok by default
echo ""
echo "[3] missing optional non-strict"
out=$(bash "$SCRIPT" --required=a --optional=b,c --available=a --no-config)
rc=$?
[ $rc -eq 0 ] && ok "3.1 exit 0" || ko "3.1 exit $rc"
[ "$(echo "$out" | jq -r '.ok')" = "true" ] && ok "3.2 ok=true" || ko "3.2"
[ "$(echo "$out" | jq -r '.missing_optional | sort | join(",")')" = "b,c" ] && ok "3.3 optional listed" || ko "3.3"

# 4. --strict-optional → fail on missing optional
echo ""
echo "[4] strict optional"
out=$(bash "$SCRIPT" --required=a --optional=b --available=a --no-config --strict-optional); rc=$?
[ $rc -eq 1 ] && ok "4.1 exit 1" || ko "4.1 exit $rc"
[ "$(echo "$out" | jq -r '.ok')" = "false" ] && ok "4.2 ok=false" || ko "4.2"

# 5. Empty inputs all → ok
echo ""
echo "[5] empty inputs"
out=$(bash "$SCRIPT" --available=a --no-config)
rc=$?
[ $rc -eq 0 ] && ok "5.1 exit 0" || ko "5.1 exit $rc"
[ "$(echo "$out" | jq -r '.missing_required | length')" = "0" ] && ok "5.2 no req missing" || ko "5.2"

# 6. Output is valid JSON
echo ""
echo "[6] valid JSON"
out=$(bash "$SCRIPT" --required=a --available=a --no-config)
echo "$out" | jq empty 2>/dev/null && ok "6.1 valid" || ko "6.1 invalid: $out"

# 7. SNAP_MCP_AVAILABLE env fallback
echo ""
echo "[7] env fallback"
out=$(SNAP_MCP_AVAILABLE="x,y" bash "$SCRIPT" --required=x --no-config)
[ "$(echo "$out" | jq -r '.ok')" = "true" ] && ok "7.1 env used" || ko "7.1"
[ "$(echo "$out" | jq -r '.available | join(",")')" = "x,y" ] && ok "7.2 env contents" || ko "7.2"

# 8. --available overrides env
echo ""
echo "[8] --available overrides env"
out=$(SNAP_MCP_AVAILABLE="x,y" bash "$SCRIPT" --required=a --available=a --no-config)
[ "$(echo "$out" | jq -r '.ok')" = "true" ] && ok "8.1 explicit wins" || ko "8.1"

# 9. Reads required from config
echo ""
echo "[9] config-driven required"
TMP=$(mktemp -d)
cat > "$TMP/snapship.config.json" <<'EOF'
{
  "version": "1.0",
  "ai": {
    "mcp_servers_required": ["frame0", "affine"],
    "mcp_servers_optional": ["playwright"]
  }
}
EOF
out=$(bash "$SCRIPT" --project-root="$TMP" --available=frame0,affine,playwright)
rc=$?
[ $rc -eq 0 ] && ok "9.1 exit 0" || ko "9.1 exit $rc"
[ "$(echo "$out" | jq -r '.available | length')" = "3" ] && ok "9.2 available count" || ko "9.2"

# 10. config-driven missing
echo ""
echo "[10] config required missing"
out=$(bash "$SCRIPT" --project-root="$TMP" --available=frame0); rc=$?
[ $rc -eq 1 ] && ok "10.1 exit 1" || ko "10.1 exit $rc"
[ "$(echo "$out" | jq -r '.missing_required | join(",")')" = "affine" ] && ok "10.2 affine missing" || ko "10.2"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

# 11. --no-config skips config
echo ""
echo "[11] --no-config skip"
TMP=$(mktemp -d)
cat > "$TMP/snapship.config.json" <<'EOF'
{ "version": "1.0", "ai": { "mcp_servers_required": ["nope"] } }
EOF
out=$(bash "$SCRIPT" --project-root="$TMP" --available=anything --no-config)
[ "$(echo "$out" | jq -r '.missing_required | length')" = "0" ] && ok "11.1 config ignored" || ko "11.1"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"
unset TMP

# 12. Unknown flag rejected
echo ""
echo "[12] unknown arg"
bash "$SCRIPT" --foo=bar >/dev/null 2>&1
[ $? -eq 2 ] && ok "12.1 exit 2 on bad arg" || ko "12.1"

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
