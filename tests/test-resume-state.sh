#!/usr/bin/env bash
# Tests for skills/_shared/resume-state.sh

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/skills/_shared/resume-state.sh"
UPDATE="${ROOT}/skills/_shared/update-progress.sh"

PASS=0
FAIL=0
ERRORS=()

setup_dir() { mktemp -d -t snap-resume-XXXXXX; }
ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

# 1. no progress.md → exit 1, default step-00-init
echo "[1] no progress.md"
DIR=$(setup_dir)
mkdir -p "$DIR/.claude/product"
set +e
OUT=$(bash "$SCRIPT" next --skill=define --project-root="$DIR" 2>/dev/null)
RC=$?
set -e
[ "$RC" = "1" ] && ok "1.1 exit 1 when no progress.md" || ko "1.1 got rc=$RC"
ns=$(echo "$OUT" | jq -r '.next_step')
[ "$ns" = "step-00-init" ] && ok "1.2 default next_step=step-00-init" || ko "1.2 got $ns"
matched=$(echo "$OUT" | jq -r '.matched')
[ "$matched" = "false" ] && ok "1.3 matched=false" || ko "1.3 got $matched"
trash "$DIR" 2>/dev/null || true

# 2. last step ok → next NN
echo ""
echo "[2] last step ok → increment NN"
DIR=$(setup_dir)
bash "$UPDATE" --project-root="$DIR" --feature-id=_global --step-num=00 --step-name=init --status=ok --skill=define >/dev/null
bash "$UPDATE" --project-root="$DIR" --feature-id=_global --step-num=01 --step-name=vision --status=ok --skill=define >/dev/null
OUT=$(bash "$SCRIPT" next --skill=define --project-root="$DIR")
ns=$(echo "$OUT" | jq -r '.next_step')
[ "$ns" = "step-02" ] && ok "2.1 next_step=step-02" || ko "2.1 got $ns"
matched=$(echo "$OUT" | jq -r '.matched')
[ "$matched" = "true" ] && ok "2.2 matched=true" || ko "2.2 got $matched"
trash "$DIR" 2>/dev/null || true

# 3. last step skip → still increment
echo ""
echo "[3] last step skip → increment"
DIR=$(setup_dir)
bash "$UPDATE" --project-root="$DIR" --feature-id=_global --step-num=00 --step-name=init --status=ok --skill=define >/dev/null
bash "$UPDATE" --project-root="$DIR" --feature-id=_global --step-num=02 --step-name=personas --status=skip --skill=define >/dev/null
OUT=$(bash "$SCRIPT" next --skill=define --project-root="$DIR")
ns=$(echo "$OUT" | jq -r '.next_step')
[ "$ns" = "step-03" ] && ok "3.1 next_step=step-03 after skip" || ko "3.1 got $ns"
trash "$DIR" 2>/dev/null || true

# 4. last step fail → not matched, no advance
echo ""
echo "[4] last step fail ignored"
DIR=$(setup_dir)
bash "$UPDATE" --project-root="$DIR" --feature-id=_global --step-num=00 --step-name=init --status=ok --skill=define >/dev/null
bash "$UPDATE" --project-root="$DIR" --feature-id=_global --step-num=01 --step-name=vision --status=fail --skill=define >/dev/null
OUT=$(bash "$SCRIPT" next --skill=define --project-root="$DIR")
ns=$(echo "$OUT" | jq -r '.next_step')
# last ok step is 00 → next is step-01
[ "$ns" = "step-01" ] && ok "4.1 fail does not advance, next=step-01" || ko "4.1 got $ns"
trash "$DIR" 2>/dev/null || true

# 5. partial match: exact slug
echo ""
echo "[5] feature partial match"
DIR=$(setup_dir)
mkdir -p "$DIR/.claude/product/features/01-auth"
mkdir -p "$DIR/.claude/product/features/02-billing"
bash "$UPDATE" --project-root="$DIR" --feature-id=01-auth --step-num=03 --step-name=features --status=ok --skill=define >/dev/null
OUT=$(bash "$SCRIPT" next --skill=define --feature=01-auth --project-root="$DIR")
fid=$(echo "$OUT" | jq -r '.feature_id')
[ "$fid" = "01-auth" ] && ok "5.1 exact match resolves 01-auth" || ko "5.1 got $fid"
ns=$(echo "$OUT" | jq -r '.next_step')
[ "$ns" = "step-04" ] && ok "5.2 next_step=step-04 from per-feature progress" || ko "5.2 got $ns"
trash "$DIR" 2>/dev/null || true

# 6. partial match: numeric prefix
echo ""
echo "[6] numeric prefix match"
DIR=$(setup_dir)
mkdir -p "$DIR/.claude/product/features/01-auth"
mkdir -p "$DIR/.claude/product/features/02-billing"
bash "$UPDATE" --project-root="$DIR" --feature-id=01-auth --step-num=02 --step-name=personas --status=ok --skill=define >/dev/null
OUT=$(bash "$SCRIPT" next --skill=define --feature=01 --project-root="$DIR")
fid=$(echo "$OUT" | jq -r '.feature_id')
[ "$fid" = "01-auth" ] && ok "6.1 '01' resolves to 01-auth" || ko "6.1 got $fid"
trash "$DIR" 2>/dev/null || true

# 7. partial match: slug prefix
echo ""
echo "[7] slug prefix match"
DIR=$(setup_dir)
mkdir -p "$DIR/.claude/product/features/01-auth"
mkdir -p "$DIR/.claude/product/features/02-billing"
bash "$UPDATE" --project-root="$DIR" --feature-id=02-billing --step-num=01 --step-name=vision --status=ok --skill=define >/dev/null
OUT=$(bash "$SCRIPT" next --skill=define --feature=bill --project-root="$DIR")
fid=$(echo "$OUT" | jq -r '.feature_id')
[ "$fid" = "02-billing" ] && ok "7.1 'bill' resolves to 02-billing" || ko "7.1 got $fid"
trash "$DIR" 2>/dev/null || true

# 8. case insensitive
echo ""
echo "[8] case insensitive"
DIR=$(setup_dir)
mkdir -p "$DIR/.claude/product/features/01-auth"
bash "$UPDATE" --project-root="$DIR" --feature-id=01-auth --step-num=01 --step-name=vision --status=ok --skill=define >/dev/null
OUT=$(bash "$SCRIPT" next --skill=define --feature=AUTH --project-root="$DIR")
fid=$(echo "$OUT" | jq -r '.feature_id')
[ "$fid" = "01-auth" ] && ok "8.1 'AUTH' resolves case-insensitive" || ko "8.1 got $fid"
trash "$DIR" 2>/dev/null || true

# 9. ambiguous match → exit 1
echo ""
echo "[9] ambiguous slug match"
DIR=$(setup_dir)
mkdir -p "$DIR/.claude/product/features/01-auth"
mkdir -p "$DIR/.claude/product/features/02-authorization"
set +e
bash "$SCRIPT" next --skill=define --feature=auth --project-root="$DIR" 2>/dev/null
RC=$?
set -e
[ "$RC" = "1" ] && ok "9.1 ambiguous → exit 1" || ko "9.1 got rc=$RC"
trash "$DIR" 2>/dev/null || true

# 10. unmatched feature → exit 1
echo ""
echo "[10] unmatched feature"
DIR=$(setup_dir)
mkdir -p "$DIR/.claude/product/features/01-auth"
set +e
bash "$SCRIPT" next --skill=define --feature=zzz --project-root="$DIR" 2>/dev/null
RC=$?
set -e
[ "$RC" = "1" ] && ok "10.1 unmatched → exit 1" || ko "10.1 got rc=$RC"
trash "$DIR" 2>/dev/null || true

# 11. per-feature progress preferred over global
echo ""
echo "[11] per-feature progress wins"
DIR=$(setup_dir)
mkdir -p "$DIR/.claude/product/features/01-auth"
# global progress: step-01
bash "$UPDATE" --project-root="$DIR" --feature-id=_global --step-num=01 --step-name=vision --status=ok --skill=define >/dev/null
# per-feature progress: step-03
bash "$UPDATE" --project-root="$DIR" --feature-id=01-auth --step-num=03 --step-name=features --status=ok --skill=define >/dev/null
OUT=$(bash "$SCRIPT" next --skill=define --feature=01-auth --project-root="$DIR")
ns=$(echo "$OUT" | jq -r '.next_step')
[ "$ns" = "step-04" ] && ok "11.1 reads per-feature file when feature given" || ko "11.1 got $ns"
trash "$DIR" 2>/dev/null || true

# 12. skill filter (define vs ticket)
echo ""
echo "[12] skill filter"
DIR=$(setup_dir)
bash "$UPDATE" --project-root="$DIR" --feature-id=_global --step-num=00 --step-name=init --status=ok --skill=define >/dev/null
bash "$UPDATE" --project-root="$DIR" --feature-id=_global --step-num=05 --step-name=publish --status=ok --skill=ticket >/dev/null
OUT=$(bash "$SCRIPT" next --skill=define --project-root="$DIR")
ns=$(echo "$OUT" | jq -r '.next_step')
[ "$ns" = "step-01" ] && ok "12.1 define skill filter ignores ticket entries" || ko "12.1 got $ns"
trash "$DIR" 2>/dev/null || true

# 13. bad args → exit 2
echo ""
echo "[13] bad args"
set +e
bash "$SCRIPT" next 2>/dev/null
RC=$?
set -e
[ "$RC" = "2" ] && ok "13.1 missing --skill → exit 2" || ko "13.1 got rc=$RC"
set +e
bash "$SCRIPT" --bogus 2>/dev/null
RC=$?
set -e
[ "$RC" = "2" ] && ok "13.2 unknown subcommand → exit 2" || ko "13.2 got rc=$RC"

# 14. JSON output well-formed on success
echo ""
echo "[14] JSON well-formed"
DIR=$(setup_dir)
bash "$UPDATE" --project-root="$DIR" --feature-id=_global --step-num=02 --step-name=personas --status=ok --skill=define >/dev/null
OUT=$(bash "$SCRIPT" next --skill=define --project-root="$DIR")
echo "$OUT" | jq empty 2>/dev/null && ok "14.1 stdout is valid JSON" || ko "14.1"
trash "$DIR" 2>/dev/null || true

# 15. --mode filter narrows to matching mode lines (generic multi-variant infra)
echo ""
echo "[15] --mode filter (multi-variant resume)"
DIR=$(setup_dir)
bash "$UPDATE" --project-root="$DIR" --feature-id=_global --step-num=00 --step-name=init      --status=ok --skill=define --extra='{"mode":"variant-a"}' >/dev/null
bash "$UPDATE" --project-root="$DIR" --feature-id=_global --step-num=01 --step-name=intake    --status=ok --skill=define --extra='{"mode":"variant-a"}' >/dev/null
bash "$UPDATE" --project-root="$DIR" --feature-id=_global --step-num=00 --step-name=init      --status=ok --skill=define --extra='{"mode":"variant-b"}' >/dev/null

OUT=$(bash "$SCRIPT" next --skill=define --mode=variant-a --project-root="$DIR")
ns=$(echo "$OUT" | jq -r '.next_step')
[ "$ns" = "step-02" ] && ok "15.1 variant-a resume points to step-02" || ko "15.1 got $ns"

OUT=$(bash "$SCRIPT" next --skill=define --mode=variant-b --project-root="$DIR")
ns=$(echo "$OUT" | jq -r '.next_step')
[ "$ns" = "step-01" ] && ok "15.2 variant-b resume points to step-01" || ko "15.2 got $ns"

set +e
OUT=$(bash "$SCRIPT" next --skill=define --mode=variant-c --project-root="$DIR")
RC=$?
set -e
[ "$RC" = "1" ] && ok "15.3 variant-c with no prior runs → rc=1" || ko "15.3 got rc=$RC"
matched=$(echo "$OUT" | jq -r '.matched')
[ "$matched" = "false" ] && ok "15.4 matched=false for missing mode" || ko "15.4 got $matched"
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
