#!/usr/bin/env bash
# Tests for skills/_shared/domains-state.sh

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/skills/_shared/domains-state.sh"

PASS=0
FAIL=0
ERRORS=()

setup_dir() { mktemp -d -t snap-domst-XXXXXX; }
ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

echo "=== domains-state.sh tests ==="

# 1. init creates empty file
echo ""
echo "[1] init"
DIR=$(setup_dir)
bash "$SCRIPT" init --project-root="$DIR"
F="${DIR}/.claude/product/domains.json"
[ -f "$F" ] && ok "1.1 file created" || ko "1.1 missing"
[ "$(cat "$F" | jq -r 'type')" = "object" ] && ok "1.2 root is object" || ko "1.2"
[ "$(cat "$F" | jq 'length')" = "0" ] && ok "1.3 starts empty" || ko "1.3"
trash "$DIR" 2>/dev/null || true

# 2. add-domain inserts
echo ""
echo "[2] add-domain"
DIR=$(setup_dir)
bash "$SCRIPT" init --project-root="$DIR"
bash "$SCRIPT" add-domain auth "Authentication" "page-auth-1" "https://example.com/p/auth" \
  --project-root="$DIR"
F="${DIR}/.claude/product/domains.json"
[ "$(jq -r '.auth.title' "$F")" = "Authentication" ] && ok "2.1 title set" || ko "2.1"
[ "$(jq -r '.auth.domain_page_id' "$F")" = "page-auth-1" ] && ok "2.2 page_id set" || ko "2.2"
[ "$(jq -r '.auth.domain_url' "$F")" = "https://example.com/p/auth" ] && ok "2.3 url set" || ko "2.3"
[ "$(jq -r '.auth.created_at' "$F" | head -c 4)" = "20"* ] && ok "2.4 created_at set" \
  || [ -n "$(jq -r '.auth.created_at' "$F")" ] && ok "2.4 created_at set" || ko "2.4"
trash "$DIR" 2>/dev/null || true

# 3. add-domain idempotent — preserves existing journeys
echo ""
echo "[3] add-domain idempotent"
DIR=$(setup_dir)
bash "$SCRIPT" init --project-root="$DIR"
bash "$SCRIPT" add-domain auth "Authentication" "page-auth-1" --project-root="$DIR"
bash "$SCRIPT" add-journey auth signup-flow "Signup" "page-signup-1" --project-root="$DIR"
# re-add the domain — journeys must survive
bash "$SCRIPT" add-domain auth "Authentication v2" "page-auth-2" --project-root="$DIR"
F="${DIR}/.claude/product/domains.json"
[ "$(jq -r '.auth.title' "$F")" = "Authentication v2" ] && ok "3.1 title overwritten" || ko "3.1"
[ "$(jq -r '.auth.domain_page_id' "$F")" = "page-auth-2" ] && ok "3.2 page_id overwritten" || ko "3.2"
[ "$(jq -r '.auth.journeys["signup-flow"].page_id' "$F")" = "page-signup-1" ] \
  && ok "3.3 journey preserved" || ko "3.3"
trash "$DIR" 2>/dev/null || true

# 4. add-journey requires existing domain
echo ""
echo "[4] add-journey on missing domain"
DIR=$(setup_dir)
bash "$SCRIPT" init --project-root="$DIR"
if bash "$SCRIPT" add-journey ghost flow "X" "p-x" --project-root="$DIR" 2>/dev/null; then
  ko "4.1 should have rejected"
else
  ok "4.1 rejected missing domain"
fi
trash "$DIR" 2>/dev/null || true

# 5. get-domain / get-journey
echo ""
echo "[5] get-domain / get-journey"
DIR=$(setup_dir)
bash "$SCRIPT" init --project-root="$DIR"
bash "$SCRIPT" add-domain auth "Auth" "p-auth" --project-root="$DIR"
bash "$SCRIPT" add-journey auth signup-flow "Signup" "p-signup" --project-root="$DIR"
out=$(bash "$SCRIPT" get-domain auth --project-root="$DIR")
[ "$(echo "$out" | jq -r '.domain_page_id')" = "p-auth" ] && ok "5.1 get-domain" || ko "5.1"
out=$(bash "$SCRIPT" get-journey auth signup-flow --project-root="$DIR")
[ "$(echo "$out" | jq -r '.page_id')" = "p-signup" ] && ok "5.2 get-journey" || ko "5.2"
out=$(bash "$SCRIPT" get-domain ghost --project-root="$DIR")
[ -z "$out" ] || [ "$out" = "null" ] && ok "5.3 missing domain returns empty/null" || ko "5.3 got '$out'"
trash "$DIR" 2>/dev/null || true

# 6. list-domains / list-journeys
echo ""
echo "[6] list"
DIR=$(setup_dir)
bash "$SCRIPT" init --project-root="$DIR"
bash "$SCRIPT" add-domain auth "Auth" "p-auth" --project-root="$DIR"
bash "$SCRIPT" add-domain dashboard "Dashboard" "p-dash" --project-root="$DIR"
bash "$SCRIPT" add-journey auth signup-flow "Signup" "p-signup" --project-root="$DIR"
bash "$SCRIPT" add-journey auth login-flow "Login" "p-login" --project-root="$DIR"
domains=$(bash "$SCRIPT" list-domains --project-root="$DIR" | sort | tr '\n' ' ')
[ "$domains" = "auth dashboard " ] && ok "6.1 list-domains" || ko "6.1 got '$domains'"
journeys=$(bash "$SCRIPT" list-journeys auth --project-root="$DIR" | sort | tr '\n' ' ')
[ "$journeys" = "login-flow signup-flow " ] && ok "6.2 list-journeys auth" || ko "6.2 got '$journeys'"
trash "$DIR" 2>/dev/null || true

# 7. has-domain / has-journey
echo ""
echo "[7] has-*"
DIR=$(setup_dir)
bash "$SCRIPT" init --project-root="$DIR"
bash "$SCRIPT" add-domain auth "Auth" "p-auth" --project-root="$DIR"
bash "$SCRIPT" add-journey auth signup "Signup" "p-signup" --project-root="$DIR"
bash "$SCRIPT" has-domain auth --project-root="$DIR" 2>/dev/null && ok "7.1 has-domain auth" || ko "7.1"
bash "$SCRIPT" has-domain ghost --project-root="$DIR" 2>/dev/null && ko "7.2" || ok "7.2 has-domain ghost rejected"
bash "$SCRIPT" has-journey auth signup --project-root="$DIR" 2>/dev/null && ok "7.3 has-journey" || ko "7.3"
bash "$SCRIPT" has-journey auth ghost --project-root="$DIR" 2>/dev/null && ko "7.4" || ok "7.4 missing journey rejected"
trash "$DIR" 2>/dev/null || true

# 8. validate against schema
echo ""
echo "[8] validate"
DIR=$(setup_dir)
bash "$SCRIPT" init --project-root="$DIR"
bash "$SCRIPT" add-domain auth "Auth" "p-auth" --project-root="$DIR"
bash "$SCRIPT" add-journey auth signup-flow "Signup" "p-signup" --project-root="$DIR"
out=$(bash "$SCRIPT" validate --project-root="$DIR" 2>&1)
echo "$out" | grep -q "ok" && ok "8.1 validate ok on populated" || ko "8.1 got: $out"
# break it: write invalid content
echo '{"auth":{"title":"x"}}' > "${DIR}/.claude/product/domains.json"
out=$(bash "$SCRIPT" validate --project-root="$DIR" 2>&1)
echo "$out" | grep -qi "error\|invalid\|fail" && ok "8.2 validate fails on invalid" \
  || ko "8.2 expected fail, got: $out"
trash "$DIR" 2>/dev/null || true

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
