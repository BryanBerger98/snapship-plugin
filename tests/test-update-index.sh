#!/usr/bin/env bash
# Tests for skills/_shared/update-index.sh

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETUP="${ROOT}/skills/_shared/setup-product-dir.sh"
SCRIPT="${ROOT}/skills/_shared/update-index.sh"

PASS=0
FAIL=0
ERRORS=()

setup_dir() {
  local d
  d=$(mktemp -d -t artysan-updidx-XXXXXX)
  bash "$SETUP" --project-root="$d" >/dev/null
  echo "$d"
}

ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

cell() {
  local file="$1" fid="$2" col="$3"
  grep -E "^\| ${fid} +\|" "$file" | awk -F'|' -v c="$col" '
    { v=$c; gsub(/^ +| +$/, "", v); print v }
  ' | head -1
}

echo "=== update-index.sh tests ==="

# 1. Append new row
echo ""
echo "[1] Append new row"
DIR=$(setup_dir)
bash "$SCRIPT" --project-root="$DIR" --feature-id=01-auth --feature-name="Auth" --state=defined >/dev/null
INDEX="${DIR}/.claude/product/index.md"
[ "$(cell "$INDEX" 01-auth 2)" = "01-auth" ] && ok "1.1 row inserted" || ko "1.1 row missing"
[ "$(cell "$INDEX" 01-auth 3)" = "Auth" ] && ok "1.2 name set" || ko "1.2 name = $(cell "$INDEX" 01-auth 3)"
[ "$(cell "$INDEX" 01-auth 4)" = "defined" ] && ok "1.3 state = defined" || ko "1.3 state = $(cell "$INDEX" 01-auth 4)"
[ "$(cell "$INDEX" 01-auth 5)" = "-" ] && ok "1.4 affine default '-'" || ko "1.4 affine = $(cell "$INDEX" 01-auth 5)"
trash "$DIR" 2>/dev/null || true

# 2. Update existing row, preserve other fields
echo ""
echo "[2] Update preserves other fields"
DIR=$(setup_dir)
INDEX="${DIR}/.claude/product/index.md"
bash "$SCRIPT" --project-root="$DIR" --feature-id=01-auth --feature-name="Auth" --state=defined --affine="[PRD](affine://abc)" >/dev/null
bash "$SCRIPT" --project-root="$DIR" --feature-id=01-auth --state=developed --dev="8/8" >/dev/null
[ "$(cell "$INDEX" 01-auth 3)" = "Auth" ] && ok "2.1 name preserved" || ko "2.1 name = $(cell "$INDEX" 01-auth 3)"
[ "$(cell "$INDEX" 01-auth 4)" = "developed" ] && ok "2.2 state updated" || ko "2.2 state = $(cell "$INDEX" 01-auth 4)"
[ "$(cell "$INDEX" 01-auth 5)" = "[PRD](affine://abc)" ] && ok "2.3 affine preserved" || ko "2.3 affine = $(cell "$INDEX" 01-auth 5)"
[ "$(cell "$INDEX" 01-auth 8)" = "8/8" ] && ok "2.4 dev updated" || ko "2.4 dev = $(cell "$INDEX" 01-auth 8)"
trash "$DIR" 2>/dev/null || true

# 3. Multiple features
echo ""
echo "[3] Multiple features"
DIR=$(setup_dir)
INDEX="${DIR}/.claude/product/index.md"
bash "$SCRIPT" --project-root="$DIR" --feature-id=01-auth --feature-name="Auth" >/dev/null
bash "$SCRIPT" --project-root="$DIR" --feature-id=02-dashboard --feature-name="Dashboard" --state=ticketed >/dev/null
bash "$SCRIPT" --project-root="$DIR" --feature-id=03-notif --feature-name="Notifications" >/dev/null
count=$(grep -cE "^\| 0[1-3]-" "$INDEX")
[ "$count" -eq 3 ] && ok "3.1 three rows present" || ko "3.1 row count = $count"
[ "$(cell "$INDEX" 02-dashboard 4)" = "ticketed" ] && ok "3.2 02-dashboard state" || ko "3.2 02 state = $(cell "$INDEX" 02-dashboard 4)"
trash "$DIR" 2>/dev/null || true

# 4. Idempotent re-run with same args
echo ""
echo "[4] Idempotent identical re-run"
DIR=$(setup_dir)
INDEX="${DIR}/.claude/product/index.md"
bash "$SCRIPT" --project-root="$DIR" --feature-id=01-auth --feature-name="Auth" --state=defined >/dev/null
hash_before=$(shasum "$INDEX" | awk '{print $1}')
bash "$SCRIPT" --project-root="$DIR" --feature-id=01-auth --feature-name="Auth" --state=defined >/dev/null
hash_after=$(shasum "$INDEX" | awk '{print $1}')
[ "$hash_before" = "$hash_after" ] && ok "4.1 file hash stable" || ko "4.1 hash differs ($hash_before vs $hash_after)"
trash "$DIR" 2>/dev/null || true

# 5. Invalid arg rejection
echo ""
echo "[5] Invalid args rejected"
DIR=$(setup_dir)
bash "$SCRIPT" --project-root="$DIR" --feature-id=01-auth --state=invalid >/dev/null 2>&1
[ $? -ne 0 ] && ok "5.1 invalid state rejected" || ko "5.1 invalid state accepted"
bash "$SCRIPT" --project-root="$DIR" --feature-id=auth --feature-name=X >/dev/null 2>&1
[ $? -ne 0 ] && ok "5.2 invalid feature_id rejected" || ko "5.2 invalid feature_id accepted"
bash "$SCRIPT" --project-root="$DIR" --state=defined >/dev/null 2>&1
[ $? -ne 0 ] && ok "5.3 missing --feature-id rejected" || ko "5.3 missing --feature-id accepted"
trash "$DIR" 2>/dev/null || true

# 6. index.md missing → error
echo ""
echo "[6] Missing index.md"
DIR=$(mktemp -d -t artysan-noidx-XXXXXX)
bash "$SCRIPT" --project-root="$DIR" --feature-id=01-auth --feature-name=X >/dev/null 2>&1
[ $? -ne 0 ] && ok "6.1 fails when index.md absent" || ko "6.1 succeeded without index.md"
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
