#!/usr/bin/env bash
# Tests for skills/_shared/severity-gate.sh
# Real cases: every severity (none/info/minor/major/critical) against every
# threshold, asserting block vs pass on each ordering boundary. No mocks.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/skills/_shared/severity-gate.sh"

PASS=0
FAIL=0
ERRORS=()

ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

# verdict mode: assert stdout == expected ("block"|"pass")
expect_verdict() {
  local sev="$1" thr="$2" want="$3"
  local got
  got=$(bash "$SCRIPT" --severity="$sev" --threshold="$thr" 2>/dev/null)
  [[ "$got" = "$want" ]] \
    && ok "verdict sev=$sev thr=$thr -> $want" \
    || ko "verdict sev=$sev thr=$thr expected $want got '$got'"
}

# gate mode: assert exit code (0=block, 10=pass)
expect_gate() {
  local sev="$1" thr="$2" want="$3"
  bash "$SCRIPT" --severity="$sev" --threshold="$thr" --mode=gate >/dev/null 2>&1
  local rc=$?
  [[ "$rc" -eq "$want" ]] \
    && ok "gate sev=$sev thr=$thr -> exit $want" \
    || ko "gate sev=$sev thr=$thr expected exit $want got $rc"
}

echo "=== severity-gate.sh tests ==="

# [1] threshold=info — anything >= info blocks; none passes.
echo ""
echo "[1] threshold=info"
expect_verdict none     info pass
expect_verdict info     info block
expect_verdict minor    info block
expect_verdict major    info block
expect_verdict critical info block

# [2] threshold=minor — boundary at minor.
echo ""
echo "[2] threshold=minor"
expect_verdict none     minor pass
expect_verdict info     minor pass
expect_verdict minor    minor block
expect_verdict major    minor block
expect_verdict critical minor block

# [3] threshold=major — boundary at major.
echo ""
echo "[3] threshold=major"
expect_verdict none     major pass
expect_verdict info     major pass
expect_verdict minor    major pass
expect_verdict major    major block
expect_verdict critical major block

# [4] threshold=critical — only critical blocks.
echo ""
echo "[4] threshold=critical"
expect_verdict none     critical pass
expect_verdict info     critical pass
expect_verdict minor    critical pass
expect_verdict major    critical pass
expect_verdict critical critical block

# [5] gate mode exit codes (0=block, 10=pass).
echo ""
echo "[5] gate mode exit codes"
expect_gate major    minor 0   # blocks
expect_gate info     minor 10  # passes
expect_gate none     info  10  # none always passes
expect_gate critical critical 0
expect_gate minor    major 10

# [6] real-world defaults — security threshold=info catches info findings.
echo ""
echo "[6] config defaults (technical/functional=minor, security=info)"
expect_verdict info  info  block   # security: info finding blocks
expect_verdict info  minor pass    # technical/functional: info finding passes
expect_verdict minor minor block   # technical/functional: minor finding blocks

# [7] error handling.
echo ""
echo "[7] error handling"
bash "$SCRIPT" --severity=bogus --threshold=minor >/dev/null 2>&1
[[ $? -eq 1 ]] && ok "7.1 invalid severity rejected" || ko "7.1 invalid severity accepted"
bash "$SCRIPT" --severity=minor --threshold=bogus >/dev/null 2>&1
[[ $? -eq 1 ]] && ok "7.2 invalid threshold rejected" || ko "7.2 invalid threshold accepted"
bash "$SCRIPT" --threshold=minor >/dev/null 2>&1
[[ $? -eq 2 ]] && ok "7.3 missing severity rejected" || ko "7.3 missing severity accepted"
bash "$SCRIPT" --severity=minor >/dev/null 2>&1
[[ $? -eq 2 ]] && ok "7.4 missing threshold rejected" || ko "7.4 missing threshold accepted"
bash "$SCRIPT" --severity=minor --threshold=minor --mode=bogus >/dev/null 2>&1
[[ $? -eq 1 ]] && ok "7.5 invalid mode rejected" || ko "7.5 invalid mode accepted"

echo ""
echo "=== Summary ==="
echo "Passed: ${PASS}"
echo "Failed: ${FAIL}"

if [[ "$FAIL" -gt 0 ]]; then
  echo ""
  echo "Errors:"
  printf '  - %s\n' "${ERRORS[@]}"
  exit 1
fi
