#!/usr/bin/env bash
# Tests for skills/_shared/retry-policy.sh — retry decision + backoff for
# MCP failures captured by check-mcp-response.sh (V1 / Phase 23).

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/skills/_shared/retry-policy.sh"

PASS=0
FAIL=0
ERRORS=()

ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1 — $2"; FAIL=$((FAIL + 1)); ERRORS+=("$1: $2"); }

# Tighten env for fast tests (10ms base, max 2 retries).
export SNAP_MCP_RETRY_BASE_MS=10
export SNAP_MCP_RETRY_MAX=2

echo "[1] retryable reasons — within budget"

for reason in \
  "mcp: error: rate-limit" \
  "mcp: error: ratelimit hit" \
  "mcp: error: request timeout" \
  "mcp: error: network unreachable" \
  "mcp: error: transient failure" \
  "mcp: error: server-error" \
  "mcp: error: 5xx upstream" \
  "mcp: error: 502 bad gateway" \
  "mcp: error: 503 unavailable" \
  "mcp: error: 504 gateway timeout"
do
  err=$(bash "$SCRIPT" "$reason" 1 2>&1 >/dev/null); rc=$?
  if [ "$rc" -eq 0 ] && echo "$err" | grep -q "retry 1/2"; then
    ok "1.x retry on \"$reason\""
  else
    ko "1.x \"$reason\"" "rc=$rc err=$err"
  fi
done

echo ""
echo "[2] non-retryable reasons"

for reason in \
  "mcp: error: auth-fail" \
  "mcp: error: not-found" \
  "mcp: error: schema-fail" \
  "mcp: malformed-json" \
  "mcp: missing page_id" \
  "mcp: empty url"
do
  err=$(bash "$SCRIPT" "$reason" 1 2>&1 >/dev/null); rc=$?
  if [ "$rc" -eq 1 ] && echo "$err" | grep -q "non-retryable"; then
    ok "2.x reject \"$reason\""
  else
    ko "2.x \"$reason\"" "rc=$rc err=$err"
  fi
done

echo ""
echo "[3] exhaustion"

# 3.1 — ATTEMPT > MAX → exhausted
err=$(bash "$SCRIPT" "mcp: error: rate-limit" 3 2>&1 >/dev/null); rc=$?
[ "$rc" -eq 1 ] && echo "$err" | grep -q "exhausted (3/2)" && \
  ok "3.1 exhausted at attempt=3 (max=2)" || ko "3.1" "rc=$rc err=$err"

# 3.2 — boundary ATTEMPT == MAX → still retry
err=$(bash "$SCRIPT" "mcp: error: timeout" 2 2>&1 >/dev/null); rc=$?
[ "$rc" -eq 0 ] && echo "$err" | grep -q "retry 2/2" && \
  ok "3.2 boundary attempt=max → retry" || ko "3.2" "rc=$rc err=$err"

echo ""
echo "[4] env overrides"

# 4.1 — SNAP_MCP_RETRY_MAX=0 → first failure already exhausted
err=$(SNAP_MCP_RETRY_MAX=0 bash "$SCRIPT" "mcp: error: rate-limit" 1 2>&1 >/dev/null); rc=$?
[ "$rc" -eq 1 ] && echo "$err" | grep -q "exhausted (1/0)" && \
  ok "4.1 MAX=0 → no retries at all" || ko "4.1" "rc=$rc err=$err"

# 4.2 — SNAP_MCP_RETRY_MAX=5 → still retry at attempt 3
err=$(SNAP_MCP_RETRY_MAX=5 bash "$SCRIPT" "mcp: error: rate-limit" 3 2>&1 >/dev/null); rc=$?
[ "$rc" -eq 0 ] && echo "$err" | grep -q "retry 3/5" && \
  ok "4.2 MAX=5 → retry at attempt=3" || ko "4.2" "rc=$rc err=$err"

# 4.3 — non-retryable wins over budget (MAX=99 doesn't save auth-fail)
err=$(SNAP_MCP_RETRY_MAX=99 bash "$SCRIPT" "mcp: error: auth-fail" 1 2>&1 >/dev/null); rc=$?
[ "$rc" -eq 1 ] && echo "$err" | grep -q "non-retryable" && \
  ok "4.3 non-retryable beats MAX=99" || ko "4.3" "rc=$rc err=$err"

echo ""
echo "[5] backoff timing (smoke)"

# 5.1 — attempt=1 with BASE=10 → ~10ms (we cap measurement at 200ms for slack)
start=$(date +%s%N 2>/dev/null || gdate +%s%N)
SNAP_MCP_RETRY_BASE_MS=10 bash "$SCRIPT" "mcp: error: timeout" 1 >/dev/null 2>&1
end=$(date +%s%N 2>/dev/null || gdate +%s%N)
if [ -n "$start" ] && [ -n "$end" ]; then
  elapsed_ms=$(( (end - start) / 1000000 ))
  if [ "$elapsed_ms" -ge 5 ] && [ "$elapsed_ms" -le 500 ]; then
    ok "5.1 backoff ~10ms (got ${elapsed_ms}ms)"
  else
    ko "5.1" "elapsed=${elapsed_ms}ms outside [5,500]"
  fi
else
  ok "5.1 skipped (no ns-precision date)"
fi

# 5.2 — stderr announces delay + reason
err=$(SNAP_MCP_RETRY_BASE_MS=20 bash "$SCRIPT" "mcp: error: 503 unavailable" 2 2>&1 >/dev/null); rc=$?
[ "$rc" -eq 0 ] && echo "$err" | grep -q "in 40ms" && echo "$err" | grep -q "503" && \
  ok "5.2 stderr announces delay+reason" || ko "5.2" "rc=$rc err=$err"

echo ""
echo "[6] usage / arg validation"

# 6.1 — no args
bash "$SCRIPT" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "6.1 no args → rc=2" || ko "6.1" "rc=$rc"

# 6.2 — 1 arg
bash "$SCRIPT" "mcp: error: rate-limit" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "6.2 1 arg → rc=2" || ko "6.2" "rc=$rc"

# 6.3 — 3 args
bash "$SCRIPT" "mcp: error: rate-limit" 1 extra >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "6.3 3 args → rc=2" || ko "6.3" "rc=$rc"

# 6.4 — bad ATTEMPT (non-numeric)
bash "$SCRIPT" "mcp: error: rate-limit" abc >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "6.4 non-numeric ATTEMPT → rc=2" || ko "6.4" "rc=$rc"

# 6.5 — bad ATTEMPT (zero)
bash "$SCRIPT" "mcp: error: rate-limit" 0 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "6.5 ATTEMPT=0 → rc=2" || ko "6.5" "rc=$rc"

# 6.6 — bad ATTEMPT (negative)
bash "$SCRIPT" "mcp: error: rate-limit" -1 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "6.6 ATTEMPT=-1 → rc=2" || ko "6.6" "rc=$rc"

# 6.7 — bad SNAP_MCP_RETRY_MAX
SNAP_MCP_RETRY_MAX=abc bash "$SCRIPT" "mcp: error: rate-limit" 1 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "6.7 MAX=abc → rc=2" || ko "6.7" "rc=$rc"

# 6.8 — bad SNAP_MCP_RETRY_BASE_MS
SNAP_MCP_RETRY_BASE_MS=abc bash "$SCRIPT" "mcp: error: rate-limit" 1 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "6.8 BASE_MS=abc → rc=2" || ko "6.8" "rc=$rc"

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
