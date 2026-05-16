#!/usr/bin/env bash
# Tests for skills/_shared/check-mcp-response.sh — guard for MCP response
# envelopes (Q4 / Phase 13).

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/skills/_shared/check-mcp-response.sh"

PASS=0
FAIL=0
ERRORS=()

ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1 — $2"; FAIL=$((FAIL + 1)); ERRORS+=("$1: $2"); }

echo "[1] success path"

# 1.1 — valid object, key present, non-empty string → stdout value, rc 0
out=$(bash "$SCRIPT" '{"page_id":"abc-123","url":"https://x"}' page_id); rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "abc-123" ]; then
  ok "1.1 returns value on success"
else
  ko "1.1" "rc=$rc out=$out"
fi

# 1.2 — works for arbitrary key names
out=$(bash "$SCRIPT" '{"blob_id":"x-9"}' blob_id); rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "x-9" ] && ok "1.2 generic key" || ko "1.2" "rc=$rc out=$out"

# 1.3 — silent on stderr when ok
err=$(bash "$SCRIPT" '{"page_id":"p"}' page_id 2>&1 >/dev/null); rc=$?
[ "$rc" -eq 0 ] && [ -z "$err" ] && ok "1.3 stderr clean on success" || ko "1.3" "rc=$rc err=$err"

echo ""
echo "[2] error envelope rejection"

# 2.1 — explicit .error → rc 1
err=$(bash "$SCRIPT" '{"error":"rate-limit"}' page_id 2>&1 >/dev/null); rc=$?
if [ "$rc" -eq 1 ] && echo "$err" | grep -q "rate-limit"; then
  ok "2.1 rejects {error: rate-limit}"
else
  ko "2.1" "rc=$rc err=$err"
fi

# 2.2 — .error wins over a present page_id (defensive: never trust partial)
err=$(bash "$SCRIPT" '{"error":"auth-fail","page_id":"x"}' page_id 2>&1 >/dev/null); rc=$?
[ "$rc" -eq 1 ] && echo "$err" | grep -q "auth-fail" && ok "2.2 .error wins over page_id" || ko "2.2" "rc=$rc err=$err"

echo ""
echo "[3] missing / null / empty key"

# 3.1 — key absent
err=$(bash "$SCRIPT" '{"other":"x"}' page_id 2>&1 >/dev/null); rc=$?
[ "$rc" -eq 1 ] && echo "$err" | grep -q "missing page_id" && ok "3.1 key absent → missing" || ko "3.1" "rc=$rc err=$err"

# 3.2 — key null
err=$(bash "$SCRIPT" '{"page_id":null}' page_id 2>&1 >/dev/null); rc=$?
[ "$rc" -eq 1 ] && echo "$err" | grep -q "empty page_id" && ok "3.2 null → empty" || ko "3.2" "rc=$rc err=$err"

# 3.3 — key empty string
err=$(bash "$SCRIPT" '{"page_id":""}' page_id 2>&1 >/dev/null); rc=$?
[ "$rc" -eq 1 ] && echo "$err" | grep -q "empty page_id" && ok "3.3 empty string → empty" || ko "3.3" "rc=$rc err=$err"

echo ""
echo "[4] malformed JSON"

# 4.1 — non-JSON string
err=$(bash "$SCRIPT" 'not-json' page_id 2>&1 >/dev/null); rc=$?
[ "$rc" -eq 1 ] && echo "$err" | grep -q "malformed-json" && ok "4.1 raw string rejected" || ko "4.1" "rc=$rc err=$err"

# 4.2 — JSON array (not an object)
err=$(bash "$SCRIPT" '[1,2,3]' page_id 2>&1 >/dev/null); rc=$?
[ "$rc" -eq 1 ] && echo "$err" | grep -q "malformed-json" && ok "4.2 array rejected" || ko "4.2" "rc=$rc err=$err"

# 4.3 — empty string
err=$(bash "$SCRIPT" '' page_id 2>&1 >/dev/null); rc=$?
[ "$rc" -eq 1 ] && echo "$err" | grep -q "malformed-json" && ok "4.3 empty input rejected" || ko "4.3" "rc=$rc err=$err"

echo ""
echo "[5] usage"

# 5.1 — no args
bash "$SCRIPT" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "5.1 no args → rc=2" || ko "5.1" "rc=$rc"

# 5.2 — 1 arg
bash "$SCRIPT" '{"page_id":"x"}' >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "5.2 1 arg → rc=2" || ko "5.2" "rc=$rc"

# 5.3 — 3 args
bash "$SCRIPT" '{"page_id":"x"}' page_id extra >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "5.3 3 args → rc=2" || ko "5.3" "rc=$rc"

echo ""
echo "=== Summary ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "Errors:"
  for e in "${ERRORS[@]}"; do
    echo "  - $e"
  done
  exit 1
fi
