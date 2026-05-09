#!/usr/bin/env bash
# Tests for skills/_shared/detect-platforms.sh

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/skills/_shared/detect-platforms.sh"

PASS=0
FAIL=0
ERRORS=()

ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

cleanup() {
  [ -n "${TMP:-}" ] && [ -d "$TMP" ] && { trash "$TMP" 2>/dev/null || rm -rf "$TMP"; }
}
trap cleanup EXIT

unset ARTYSAN_MCP_AVAILABLE NOTION_TOKEN 2>/dev/null || true

echo "=== detect-platforms.sh tests ==="

# 1. All authenticated via overrides
echo ""
echo "[1] all auth ok"
out=$(bash "$SCRIPT" --tickets=github --docs=affine --wireframes=frame0 \
  --available=affine,frame0 --mock-cli=gh:true)
rc=$?
[ $rc -eq 0 ] && ok "1.1 exit 0" || ko "1.1 exit $rc"
[ "$(echo "$out" | jq -r '.ok')" = "true" ] && ok "1.2 overall ok" || ko "1.2"
[ "$(echo "$out" | jq -r '.tickets.ok')" = "true" ] && ok "1.3 tickets ok" || ko "1.3"
[ "$(echo "$out" | jq -r '.tickets.method')" = "cli" ] && ok "1.4 tickets cli" || ko "1.4"
[ "$(echo "$out" | jq -r '.documentation.ok')" = "true" ] && ok "1.5 docs ok" || ko "1.5"
[ "$(echo "$out" | jq -r '.wireframes.method')" = "mcp" ] && ok "1.6 wireframes mcp" || ko "1.6"

# 2. github not authenticated
echo ""
echo "[2] gh not authed"
out=$(bash "$SCRIPT" --tickets=github --mock-cli=gh:false --available=)
[ "$(echo "$out" | jq -r '.tickets.ok')" = "false" ] && ok "2.1 false" || ko "2.1"
[ "$(echo "$out" | jq -r '.tickets.detail')" = "gh present but not authenticated" ] && ok "2.2 detail" || ko "2.2"

# 3. gitlab via mock
echo ""
echo "[3] gitlab"
out=$(bash "$SCRIPT" --tickets=gitlab --mock-cli=glab:true --available=)
[ "$(echo "$out" | jq -r '.tickets.ok')" = "true" ] && ok "3.1 glab ok" || ko "3.1"

# 4. jira via MCP available
echo ""
echo "[4] jira mcp"
out=$(bash "$SCRIPT" --tickets=jira --available=jira)
[ "$(echo "$out" | jq -r '.tickets.ok')" = "true" ] && ok "4.1 jira ok" || ko "4.1"
out=$(bash "$SCRIPT" --tickets=jira --available=atlassian)
[ "$(echo "$out" | jq -r '.tickets.ok')" = "true" ] && ok "4.2 atlassian alias" || ko "4.2"
out=$(bash "$SCRIPT" --tickets=jira --available=foo)
[ "$(echo "$out" | jq -r '.tickets.ok')" = "false" ] && ok "4.3 jira missing" || ko "4.3"

# 5. notion via NOTION_TOKEN env
echo ""
echo "[5] notion env fallback"
out=$(NOTION_TOKEN=secret bash "$SCRIPT" --docs=notion --available=)
[ "$(echo "$out" | jq -r '.documentation.ok')" = "true" ] && ok "5.1 env auth" || ko "5.1"
[ "$(echo "$out" | jq -r '.documentation.method')" = "env" ] && ok "5.2 method=env" || ko "5.2"

# 6. notion no token, no MCP
echo ""
echo "[6] notion missing"
out=$(bash "$SCRIPT" --docs=notion --available=)
[ "$(echo "$out" | jq -r '.documentation.ok')" = "false" ] && ok "6.1 false" || ko "6.1"

# 7. unconfigured slot does not break overall
echo ""
echo "[7] unconfigured slot"
out=$(bash "$SCRIPT" --tickets=github --mock-cli=gh:true --available=)
[ "$(echo "$out" | jq -r '.documentation.platform')" = "" ] && ok "7.1 docs empty" || ko "7.1"
[ "$(echo "$out" | jq -r '.documentation.ok')" = "false" ] && ok "7.2 docs ok=false" || ko "7.2"
# Overall ignores empty slot → still true
[ "$(echo "$out" | jq -r '.ok')" = "true" ] && ok "7.3 overall ok" || ko "7.3 got $(echo "$out" | jq -r '.ok')"

# 8. unsupported platform
echo ""
echo "[8] unsupported platform"
out=$(bash "$SCRIPT" --tickets=foobar)
[ "$(echo "$out" | jq -r '.tickets.method')" = "unknown" ] && ok "8.1 unknown method" || ko "8.1"

# 9. --strict + missing → exit 2
echo ""
echo "[9] strict failure"
out=$(bash "$SCRIPT" --tickets=github --mock-cli=gh:false --available= --strict); rc=$?
[ $rc -eq 2 ] && ok "9.1 exit 2" || ko "9.1 exit $rc"

# 10. --strict + ok → exit 0
echo ""
echo "[10] strict success"
out=$(bash "$SCRIPT" --tickets=github --mock-cli=gh:true --available= --strict); rc=$?
[ $rc -eq 0 ] && ok "10.1 exit 0" || ko "10.1 exit $rc"

# 11. config-driven
echo ""
echo "[11] config drives slots"
TMP=$(mktemp -d)
cat > "$TMP/artysan.config.json" <<'EOF'
{
  "version": "1.0",
  "tickets": { "platform": "github" },
  "documentation": { "platform": "affine" },
  "wireframes": { "platform": "frame0" }
}
EOF
out=$(bash "$SCRIPT" --project-root="$TMP" --available=affine,frame0 --mock-cli=gh:true)
[ "$(echo "$out" | jq -r '.tickets.platform')" = "github" ] && ok "11.1 tickets from config" || ko "11.1"
[ "$(echo "$out" | jq -r '.documentation.platform')" = "affine" ] && ok "11.2 docs from config" || ko "11.2"
[ "$(echo "$out" | jq -r '.wireframes.platform')" = "frame0" ] && ok "11.3 wireframes from config" || ko "11.3"
[ "$(echo "$out" | jq -r '.ok')" = "true" ] && ok "11.4 overall ok" || ko "11.4"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

# 12. Override beats config
echo ""
echo "[12] override beats config"
TMP=$(mktemp -d)
cat > "$TMP/artysan.config.json" <<'EOF'
{ "version": "1.0", "tickets": { "platform": "jira" } }
EOF
out=$(bash "$SCRIPT" --project-root="$TMP" --tickets=github --mock-cli=gh:true --available=)
[ "$(echo "$out" | jq -r '.tickets.platform')" = "github" ] && ok "12.1 override applied" || ko "12.1"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"
unset TMP

# 13. Output is valid JSON
echo ""
echo "[13] valid JSON"
out=$(bash "$SCRIPT" --tickets=github --mock-cli=gh:true --available=)
echo "$out" | jq empty 2>/dev/null && ok "13.1 valid" || ko "13.1: $out"

# 14. Bad arg
echo ""
echo "[14] bad arg"
bash "$SCRIPT" --foo=bar >/dev/null 2>&1
[ $? -eq 1 ] && ok "14.1 exit 1" || ko "14.1"

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
