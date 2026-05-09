#!/usr/bin/env bash
# Tests for skills/_shared/update-progress.sh

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/skills/_shared/update-progress.sh"

PASS=0
FAIL=0
ERRORS=()

setup_dir() { mktemp -d -t artysan-updprg-XXXXXX; }

ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

echo "=== update-progress.sh tests ==="

# 1. First call creates progress.md + entry
echo ""
echo "[1] First call creates progress.md"
DIR=$(setup_dir)
bash "$SCRIPT" --project-root="$DIR" --feature-id=01-auth --step-num=02 --step-name=vision --status=ok --skill=define >/dev/null
PROG="${DIR}/.claude/product/features/01-auth/progress.md"
[ -f "$PROG" ] && ok "1.1 progress.md created" || ko "1.1 progress.md missing"
grep -q "# Progress — 01-auth" "$PROG" && ok "1.2 header present" || ko "1.2 header missing"
grep -qE "define step-02 vision — ok\$" "$PROG" && ok "1.3 entry written" || ko "1.3 entry missing"
trash "$DIR" 2>/dev/null || true

# 2. Append second entry preserves first
echo ""
echo "[2] Append preserves history"
DIR=$(setup_dir)
bash "$SCRIPT" --project-root="$DIR" --feature-id=01-auth --step-num=02 --step-name=vision --status=ok >/dev/null
bash "$SCRIPT" --project-root="$DIR" --feature-id=01-auth --step-num=03 --step-name=features --status=fail --note="user aborted" >/dev/null
PROG="${DIR}/.claude/product/features/01-auth/progress.md"
count=$(grep -cE "^- \[" "$PROG")
[ "$count" -eq 2 ] && ok "2.1 two entries present" || ko "2.1 entry count = $count"
grep -q "fail: user aborted" "$PROG" && ok "2.2 note rendered" || ko "2.2 note missing"
trash "$DIR" 2>/dev/null || true

# 3. Status enum enforced
echo ""
echo "[3] Status enum"
DIR=$(setup_dir)
for s in ok fail skip retry started; do
  bash "$SCRIPT" --project-root="$DIR" --feature-id=01-auth --step-name=t --status="$s" >/dev/null 2>&1
  [ $? -eq 0 ] && ok "3.x accept status=$s" || ko "3.x reject status=$s"
done
bash "$SCRIPT" --project-root="$DIR" --feature-id=01-auth --step-name=t --status=invalid >/dev/null 2>&1
[ $? -ne 0 ] && ok "3.6 reject invalid status" || ko "3.6 invalid status accepted"
trash "$DIR" 2>/dev/null || true

# 4. Required args
echo ""
echo "[4] Required args"
DIR=$(setup_dir)
bash "$SCRIPT" --project-root="$DIR" --step-name=t --status=ok >/dev/null 2>&1
[ $? -ne 0 ] && ok "4.1 missing feature-id rejected" || ko "4.1 missing feature-id accepted"
bash "$SCRIPT" --project-root="$DIR" --feature-id=01-auth --status=ok >/dev/null 2>&1
[ $? -ne 0 ] && ok "4.2 missing step-name rejected" || ko "4.2 missing step-name accepted"
bash "$SCRIPT" --project-root="$DIR" --feature-id=01-auth --step-name=t >/dev/null 2>&1
[ $? -ne 0 ] && ok "4.3 missing status rejected" || ko "4.3 missing status accepted"
trash "$DIR" 2>/dev/null || true

# 5. Invalid feature_id format
echo ""
echo "[5] Invalid feature_id"
DIR=$(setup_dir)
bash "$SCRIPT" --project-root="$DIR" --feature-id=auth --step-name=t --status=ok >/dev/null 2>&1
[ $? -ne 0 ] && ok "5.1 'auth' rejected" || ko "5.1 'auth' accepted"
trash "$DIR" 2>/dev/null || true

# 6. Format with all optional fields
echo ""
echo "[6] Format prefix"
DIR=$(setup_dir)
bash "$SCRIPT" --project-root="$DIR" --feature-id=01-auth --step-num=04 --step-name=write-prd --status=ok --skill=define --note="3 features captured" >/dev/null
PROG="${DIR}/.claude/product/features/01-auth/progress.md"
grep -qE "define step-04 write-prd — ok: 3 features captured\$" "$PROG" && ok "6.1 full format" || ko "6.1 format mismatch: $(grep -E 'write-prd' "$PROG")"
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
