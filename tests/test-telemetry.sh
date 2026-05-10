#!/usr/bin/env bash
# Tests for skills/_shared/telemetry.sh

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/skills/_shared/telemetry.sh"

PASS=0
FAIL=0
ERRORS=()

setup() {
  local d
  d=$(mktemp -d -t snap-tel-XXXXXX)
  echo "${d}/telemetry.log"
}

ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

echo "=== telemetry.sh tests ==="

# 1. Minimal event written
echo ""
echo "[1] Minimal event"
LOG=$(setup)
out=$(bash "$SCRIPT" --log-path="$LOG" --skill=develop --step=03a-execute --status=ok)
[ -f "$LOG" ] && ok "1.1 log file created" || ko "1.1 log file missing"
event=$(head -1 "$LOG")
[ "$(echo "$event" | jq -r '.skill')" = "develop" ] && ok "1.2 skill" || ko "1.2 skill = $(echo "$event" | jq -r '.skill')"
[ "$(echo "$event" | jq -r '.step')" = "03a-execute" ] && ok "1.3 step" || ko "1.3 step"
[ "$(echo "$event" | jq -r '.status')" = "ok" ] && ok "1.4 status" || ko "1.4 status"
echo "$event" | jq -e '.ts | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T")' >/dev/null && ok "1.5 ts ISO8601" || ko "1.5 ts format"
echo "$event" | jq -e 'has("duration_ms") | not' >/dev/null && ok "1.6 omits unset duration" || ko "1.6 duration leaked"
[ "$out" = "$event" ] && ok "1.7 stdout = event" || ko "1.7 stdout != event"
trash "$(dirname "$LOG")" 2>/dev/null || true

# 2. Full event with all optional fields
echo ""
echo "[2] Full event"
LOG=$(setup)
bash "$SCRIPT" --log-path="$LOG" \
  --skill=qa --step=01-collect --status=fail \
  --duration-ms=4521 --ticket=AUTH-3 --feature=01-auth \
  --cycle=2 --severity=major --note="regression scope=impacted" >/dev/null
event=$(head -1 "$LOG")
[ "$(echo "$event" | jq -r '.duration_ms')" = "4521" ] && ok "2.1 duration_ms numeric" || ko "2.1 duration"
[ "$(echo "$event" | jq -r '.ticket')" = "AUTH-3" ] && ok "2.2 ticket" || ko "2.2 ticket"
[ "$(echo "$event" | jq -r '.feature')" = "01-auth" ] && ok "2.3 feature" || ko "2.3 feature"
[ "$(echo "$event" | jq -r '.cycle')" = "2" ] && ok "2.4 cycle numeric" || ko "2.4 cycle"
[ "$(echo "$event" | jq -r '.severity')" = "major" ] && ok "2.5 severity" || ko "2.5 severity"
[ "$(echo "$event" | jq -r '.note')" = "regression scope=impacted" ] && ok "2.6 note" || ko "2.6 note"
trash "$(dirname "$LOG")" 2>/dev/null || true

# 3. Append (multiple events)
echo ""
echo "[3] Append multiple events"
LOG=$(setup)
for i in 1 2 3; do
  bash "$SCRIPT" --log-path="$LOG" --skill=develop --step="step-$i" --status=ok >/dev/null
done
count=$(wc -l < "$LOG" | tr -d ' ')
[ "$count" -eq 3 ] && ok "3.1 three lines appended" || ko "3.1 line count = $count"
trash "$(dirname "$LOG")" 2>/dev/null || true

# 4. Each line is valid JSON (NDJSON)
echo ""
echo "[4] NDJSON validity"
LOG=$(setup)
for i in 1 2 3; do
  bash "$SCRIPT" --log-path="$LOG" --skill=develop --step="step-$i" --status=ok --note="line $i" >/dev/null
done
all_valid=true
while IFS= read -r line; do
  echo "$line" | jq empty 2>/dev/null || all_valid=false
done < "$LOG"
[ "$all_valid" = true ] && ok "4.1 all lines valid JSON" || ko "4.1 some lines invalid"
trash "$(dirname "$LOG")" 2>/dev/null || true

# 5. Status enum
echo ""
echo "[5] Status enum"
LOG=$(setup)
bash "$SCRIPT" --log-path="$LOG" --skill=x --step=y --status=invalid >/dev/null 2>&1
[ $? -ne 0 ] && ok "5.1 invalid status rejected" || ko "5.1 invalid status accepted"
trash "$(dirname "$LOG")" 2>/dev/null || true

# 6. Severity enum
echo ""
echo "[6] Severity enum"
LOG=$(setup)
bash "$SCRIPT" --log-path="$LOG" --skill=x --step=y --status=ok --severity=BAD >/dev/null 2>&1
[ $? -ne 0 ] && ok "6.1 invalid severity rejected" || ko "6.1 invalid severity accepted"
trash "$(dirname "$LOG")" 2>/dev/null || true

# 7. Required args
echo ""
echo "[7] Required args"
LOG=$(setup)
bash "$SCRIPT" --log-path="$LOG" --step=x --status=ok >/dev/null 2>&1
[ $? -ne 0 ] && ok "7.1 missing --skill rejected" || ko "7.1 accepted"
bash "$SCRIPT" --log-path="$LOG" --skill=x --status=ok >/dev/null 2>&1
[ $? -ne 0 ] && ok "7.2 missing --step rejected" || ko "7.2 accepted"
bash "$SCRIPT" --log-path="$LOG" --skill=x --step=y >/dev/null 2>&1
[ $? -ne 0 ] && ok "7.3 missing --status rejected" || ko "7.3 accepted"
trash "$(dirname "$LOG")" 2>/dev/null || true

# 8. Rotation > 10MB
echo ""
echo "[8] Rotation > 10MB"
LOG=$(setup)
# Pre-fill log with 11MB of dummy NDJSON
yes '{"ts":"2026-01-01T00:00:00Z","skill":"x","step":"y","status":"ok"}' | head -c $((11 * 1024 * 1024)) > "$LOG"
bash "$SCRIPT" --log-path="$LOG" --skill=develop --step=z --status=ok >/dev/null
[ -f "${LOG}.1" ] && ok "8.1 .log.1 created" || ko "8.1 .log.1 missing"
new_size=$(wc -c < "$LOG" | tr -d ' ')
[ "$new_size" -lt 1000 ] && ok "8.2 fresh .log small after rotation" || ko "8.2 fresh log size = $new_size"
trash "$(dirname "$LOG")" 2>/dev/null || true

# 9. duration-ms must be integer
echo ""
echo "[9] duration-ms integer"
LOG=$(setup)
bash "$SCRIPT" --log-path="$LOG" --skill=x --step=y --status=ok --duration-ms=abc >/dev/null 2>&1
[ $? -ne 0 ] && ok "9.1 non-integer duration rejected" || ko "9.1 accepted"
trash "$(dirname "$LOG")" 2>/dev/null || true

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
