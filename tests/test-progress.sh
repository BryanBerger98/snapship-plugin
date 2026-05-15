#!/usr/bin/env bash
# Tests for skills/_shared/progress.sh
# Usage: bash tests/test-progress.sh

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/skills/_shared/progress.sh"

PASS=0
FAIL=0
ERRORS=()

setup_dir() { mktemp -d -t snap-prog-XXXXXX; }
ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

echo "=== progress.sh tests ==="

# 1. start creates file with schema_version + in_flight entry
echo ""
echo "[1] start"
DIR=$(setup_dir)
bash "$SCRIPT" start --skill=define --feature-id=01-auth --project-root="$DIR"
F="${DIR}/.snap/progress.json"
[ -f "$F" ] && ok "1.1 file created" || ko "1.1 missing"
[ "$(jq -r '.schema_version' "$F")" = "1.0.0" ] && ok "1.2 schema_version" || ko "1.2"
[ "$(jq '.in_flight | length' "$F")" = "1" ] && ok "1.3 one in_flight entry" || ko "1.3"
[ "$(jq -r '.in_flight[0].skill' "$F")" = "define" ] && ok "1.4 skill" || ko "1.4"
[ "$(jq -r '.in_flight[0].feature_id' "$F")" = "01-auth" ] && ok "1.5 feature_id" || ko "1.5"
trash "$DIR" 2>/dev/null || true

# 2. start is idempotent
echo ""
echo "[2] start idempotent"
DIR=$(setup_dir)
bash "$SCRIPT" start --skill=define --feature-id=01-auth --project-root="$DIR"
bash "$SCRIPT" start --skill=define --feature-id=01-auth --project-root="$DIR"
F="${DIR}/.snap/progress.json"
[ "$(jq '.in_flight | length' "$F")" = "1" ] && ok "2.1 still 1 entry" || ko "2.1"
trash "$DIR" 2>/dev/null || true

# 3. start two distinct skills
echo ""
echo "[3] multiple skills coexist"
DIR=$(setup_dir)
bash "$SCRIPT" start --skill=define --feature-id=01-auth --project-root="$DIR"
bash "$SCRIPT" start --skill=ticket --feature-id=01-auth --project-root="$DIR"
F="${DIR}/.snap/progress.json"
[ "$(jq '.in_flight | length' "$F")" = "2" ] && ok "3.1 two entries" || ko "3.1"
trash "$DIR" 2>/dev/null || true

# 4. invalid feature-id rejected
echo ""
echo "[4] invalid feature-id"
DIR=$(setup_dir)
if bash "$SCRIPT" start --skill=define --feature-id=BAD --project-root="$DIR" 2>/dev/null; then
  ko "4.1 should reject"
else
  ok "4.1 rejected invalid feature-id"
fi
# _global accepted
bash "$SCRIPT" start --skill=init --feature-id=_global --project-root="$DIR" && ok "4.2 _global accepted" || ko "4.2"
trash "$DIR" 2>/dev/null || true

# 5. step appends, status validated
echo ""
echo "[5] step"
DIR=$(setup_dir)
bash "$SCRIPT" start --skill=define --feature-id=01-auth --project-root="$DIR"
bash "$SCRIPT" step --skill=define --feature-id=01-auth --step-num=01 --step-name=init --status=started --project-root="$DIR"
F="${DIR}/.snap/progress.json"
[ "$(jq '.in_flight[0].steps | length' "$F")" = "1" ] && ok "5.1 step appended" || ko "5.1"
[ "$(jq -r '.in_flight[0].steps[0].status' "$F")" = "started" ] && ok "5.2 status" || ko "5.2"

# step status=ok upgrades the prior started one (same name)
bash "$SCRIPT" step --skill=define --feature-id=01-auth --step-num=01 --step-name=init --status=ok --project-root="$DIR"
[ "$(jq '.in_flight[0].steps | length' "$F")" = "1" ] && ok "5.3 still 1 step (upgrade)" || ko "5.3"
[ "$(jq -r '.in_flight[0].steps[0].status' "$F")" = "ok" ] && ok "5.4 upgraded to ok" || ko "5.4"

# new step appended
bash "$SCRIPT" step --skill=define --feature-id=01-auth --step-num=02 --step-name=brainstorm --status=ok --project-root="$DIR"
[ "$(jq '.in_flight[0].steps | length' "$F")" = "2" ] && ok "5.5 appended new step" || ko "5.5"
trash "$DIR" 2>/dev/null || true

# 6. step rejects invalid status
echo ""
echo "[6] step bad status"
DIR=$(setup_dir)
bash "$SCRIPT" start --skill=define --feature-id=01-auth --project-root="$DIR"
if bash "$SCRIPT" step --skill=define --feature-id=01-auth --step-num=01 --step-name=init --status=bogus --project-root="$DIR" 2>/dev/null; then
  ko "6.1 should reject"
else
  ok "6.1 bad status rejected"
fi
trash "$DIR" 2>/dev/null || true

# 7. step auto-starts if not started
echo ""
echo "[7] step auto-start"
DIR=$(setup_dir)
bash "$SCRIPT" step --skill=define --feature-id=01-auth --step-num=01 --step-name=init --status=started --project-root="$DIR"
F="${DIR}/.snap/progress.json"
[ "$(jq '.in_flight | length' "$F")" = "1" ] && ok "7.1 auto-started" || ko "7.1"
trash "$DIR" 2>/dev/null || true

# 8. step --note + --extra preserved
echo ""
echo "[8] step note + extra"
DIR=$(setup_dir)
bash "$SCRIPT" step --skill=define --feature-id=01-auth --step-num=01 --step-name=init --status=ok --note="ok done" --extra='{"a":1}' --project-root="$DIR"
F="${DIR}/.snap/progress.json"
[ "$(jq -r '.in_flight[0].steps[0].note' "$F")" = "ok done" ] && ok "8.1 note" || ko "8.1"
[ "$(jq -r '.in_flight[0].steps[0].extra.a' "$F")" = "1" ] && ok "8.2 extra" || ko "8.2"
trash "$DIR" 2>/dev/null || true

# 9. finish --status=ok purges entry
echo ""
echo "[9] finish ok"
DIR=$(setup_dir)
bash "$SCRIPT" start --skill=define --feature-id=01-auth --project-root="$DIR"
bash "$SCRIPT" finish --skill=define --feature-id=01-auth --status=ok --project-root="$DIR"
F="${DIR}/.snap/progress.json"
[ "$(jq '.in_flight | length' "$F")" = "0" ] && ok "9.1 purged on ok" || ko "9.1"
trash "$DIR" 2>/dev/null || true

# 10. finish --status=fail keeps entry
echo ""
echo "[10] finish fail"
DIR=$(setup_dir)
bash "$SCRIPT" start --skill=define --feature-id=01-auth --project-root="$DIR"
bash "$SCRIPT" finish --skill=define --feature-id=01-auth --status=fail --project-root="$DIR"
F="${DIR}/.snap/progress.json"
[ "$(jq '.in_flight | length' "$F")" = "1" ] && ok "10.1 kept on fail (resume)" || ko "10.1"
trash "$DIR" 2>/dev/null || true

# 11. resume — empty if not in_flight
echo ""
echo "[11] resume empty"
DIR=$(setup_dir)
out=$(bash "$SCRIPT" resume --skill=define --feature-id=01-auth --project-root="$DIR")
[ -z "$out" ] && ok "11.1 no file → empty" || ko "11.1 got: $out"
trash "$DIR" 2>/dev/null || true

# 12. resume — empty when all steps ok
echo ""
echo "[12] resume after ok"
DIR=$(setup_dir)
bash "$SCRIPT" step --skill=define --feature-id=01-auth --step-num=01 --step-name=init --status=ok --project-root="$DIR"
out=$(bash "$SCRIPT" resume --skill=define --feature-id=01-auth --project-root="$DIR")
[ -z "$out" ] && ok "12.1 empty when all ok" || ko "12.1 got: $out"
trash "$DIR" 2>/dev/null || true

# 13. resume — reports started/fail step
echo ""
echo "[13] resume reports last unfinished"
DIR=$(setup_dir)
bash "$SCRIPT" step --skill=define --feature-id=01-auth --step-num=01 --step-name=init --status=ok --project-root="$DIR"
bash "$SCRIPT" step --skill=define --feature-id=01-auth --step-num=02 --step-name=brainstorm --status=fail --project-root="$DIR"
out=$(bash "$SCRIPT" resume --skill=define --feature-id=01-auth --project-root="$DIR")
echo "$out" | grep -q "brainstorm" && ok "13.1 reports failed step" || ko "13.1 got: $out"
echo "$out" | grep -q "fail" && ok "13.2 reports status fail" || ko "13.2"
trash "$DIR" 2>/dev/null || true

# 14. list
echo ""
echo "[14] list"
DIR=$(setup_dir)
out=$(bash "$SCRIPT" list --project-root="$DIR")
[ "$out" = "[]" ] && ok "14.1 no file → []" || ko "14.1 got: $out"
bash "$SCRIPT" start --skill=define --feature-id=01-auth --project-root="$DIR"
out=$(bash "$SCRIPT" list --project-root="$DIR")
[ "$(echo "$out" | jq 'length')" = "1" ] && ok "14.2 one entry" || ko "14.2"
trash "$DIR" 2>/dev/null || true

# 15. usage / help
echo ""
echo "[15] usage"
bash "$SCRIPT" 2>/dev/null; [ $? -eq 1 ] && ok "15.1 no args = exit 1" || ko "15.1"
bash "$SCRIPT" --help >/dev/null; [ $? -eq 0 ] && ok "15.2 --help = 0" || ko "15.2"
bash "$SCRIPT" bogus 2>/dev/null; [ $? -eq 1 ] && ok "15.3 unknown subcmd = 1" || ko "15.3"

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
