#!/usr/bin/env bash
# Tests for skills/_shared/ask-or-default.sh

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/skills/_shared/ask-or-default.sh"

PASS=0
FAIL=0
ERRORS=()

ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

echo "=== ask-or-default.sh tests ==="

# 1. auto-mode=true with default → echoes default
echo ""
echo "[1] auto-mode=true with default"
out=$(bash "$SCRIPT" --auto-mode=true --question-id=test --default=jira)
[ "$out" = "jira" ] && ok "1.1 echoes default" || ko "1.1 got '$out'"

# 2. auto-mode=true without default → exit 1
echo ""
echo "[2] auto-mode=true without default"
bash "$SCRIPT" --auto-mode=true --question-id=test >/dev/null 2>&1
[ $? -ne 0 ] && ok "2.1 fails without default" || ko "2.1 succeeded"

# 3. auto-mode=true with default not in options → exit 1
echo ""
echo "[3] auto-mode=true default not in options"
bash "$SCRIPT" --auto-mode=true --question-id=test --options=a,b,c --default=z >/dev/null 2>&1
[ $? -ne 0 ] && ok "3.1 default validation rejects mismatch" || ko "3.1 mismatch accepted"

# 4. auto-mode=true with default in options → ok
echo ""
echo "[4] auto-mode=true default in options"
out=$(bash "$SCRIPT" --auto-mode=true --question-id=test --options=jira,github --default=jira)
[ "$out" = "jira" ] && ok "4.1 valid default echoed" || ko "4.1 got '$out'"

# 5. auto-mode=false → JSON instruction
echo ""
echo "[5] auto-mode=false JSON instruction"
out=$(bash "$SCRIPT" --auto-mode=false --question-id=confirm-platform \
  --question="Quel platform?" --options=jira,github,gitlab --default=jira)
[ "$(echo "$out" | jq -r '.action')" = "ask" ] && ok "5.1 action=ask" || ko "5.1 action = $(echo "$out" | jq -r '.action')"
[ "$(echo "$out" | jq -r '.question_id')" = "confirm-platform" ] && ok "5.2 question_id" || ko "5.2 question_id"
[ "$(echo "$out" | jq -r '.question')" = "Quel platform?" ] && ok "5.3 question" || ko "5.3 question"
[ "$(echo "$out" | jq -r '.options | length')" = "3" ] && ok "5.4 options count" || ko "5.4 options"
[ "$(echo "$out" | jq -r '.options[1]')" = "github" ] && ok "5.5 options[1]" || ko "5.5 options"
[ "$(echo "$out" | jq -r '.default')" = "jira" ] && ok "5.6 default" || ko "5.6 default"

# 6. auto-mode=false minimal → JSON without optional fields
echo ""
echo "[6] auto-mode=false minimal"
out=$(bash "$SCRIPT" --auto-mode=false --question-id=q1)
[ "$(echo "$out" | jq -r '.action')" = "ask" ] && ok "6.1 action present" || ko "6.1 action"
echo "$out" | jq -e 'has("question") | not' >/dev/null && ok "6.2 omits empty question" || ko "6.2 question leaked"
echo "$out" | jq -e 'has("options") | not' >/dev/null && ok "6.3 omits empty options" || ko "6.3 options leaked"

# 7. Required args
echo ""
echo "[7] Required args"
bash "$SCRIPT" --question-id=x --default=y >/dev/null 2>&1
[ $? -ne 0 ] && ok "7.1 missing --auto-mode rejected" || ko "7.1 accepted"
bash "$SCRIPT" --auto-mode=true --default=y >/dev/null 2>&1
[ $? -ne 0 ] && ok "7.2 missing --question-id rejected" || ko "7.2 accepted"
bash "$SCRIPT" --auto-mode=maybe --question-id=x >/dev/null 2>&1
[ $? -ne 0 ] && ok "7.3 invalid --auto-mode rejected" || ko "7.3 accepted"

# 8. Defaults with spaces and special chars
echo ""
echo "[8] Special chars in default"
out=$(bash "$SCRIPT" --auto-mode=true --question-id=test --default="hello world")
[ "$out" = "hello world" ] && ok "8.1 spaces preserved" || ko "8.1 got '$out'"

# 9. Header field
echo ""
echo "[9] Header field"
out=$(bash "$SCRIPT" --auto-mode=false --question-id=q --header="Auth method")
[ "$(echo "$out" | jq -r '.header')" = "Auth method" ] && ok "9.1 header" || ko "9.1 header"

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
