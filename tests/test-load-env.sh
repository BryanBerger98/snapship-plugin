#!/usr/bin/env bash
# Tests for skills/_shared/load-env.sh

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/skills/_shared/load-env.sh"

PASS=0
FAIL=0
ERRORS=()

ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

TMPDIR_BASE="$(mktemp -d -t load-env.XXXXXX)"
cleanup() { trash "$TMPDIR_BASE" 2>/dev/null || rm -rf "$TMPDIR_BASE"; }
trap cleanup EXIT

make_env() {
  local dir="$1"
  mkdir -p "$dir"
  cat > "$dir/.env.snapship" <<'EOF'
# Snapship secrets — gitignored
FIGMA_ACCESS_TOKEN=figd_plain123
QUOTED_DOUBLE="value with spaces"
QUOTED_SINGLE='single quoted'
  INDENTED=ok

# trailing comment
EMPTY_VALUE=
EOF
}

echo "=== load-env.sh tests ==="

# 1. missing --project-root → exit 2
echo ""
echo "[1] missing --project-root"
bash "$SCRIPT" --key=FOO >/dev/null 2>&1
[ $? -eq 2 ] && ok "1.1 exit 2" || ko "1.1 wrong rc"

# 2. unknown arg → exit 2
echo ""
echo "[2] unknown arg"
bash "$SCRIPT" --project-root=/tmp --bogus=x >/dev/null 2>&1
[ $? -eq 2 ] && ok "2.1 exit 2" || ko "2.1 wrong rc"

# 3. file missing → exit 1
echo ""
echo "[3] file missing"
NOFILE="$TMPDIR_BASE/nodir"
mkdir -p "$NOFILE"
bash "$SCRIPT" --project-root="$NOFILE" --key=FOO >/dev/null 2>&1
[ $? -eq 1 ] && ok "3.1 exit 1 when file absent" || ko "3.1 wrong rc"

# 4. plain key lookup
echo ""
echo "[4] plain key"
D1="$TMPDIR_BASE/p1"; make_env "$D1"
out=$(bash "$SCRIPT" --project-root="$D1" --key=FIGMA_ACCESS_TOKEN)
[ "$out" = "figd_plain123" ] && ok "4.1 plain value" || ko "4.1 got '$out'"

# 5. double-quoted value stripped
echo ""
echo "[5] double-quoted value"
out=$(bash "$SCRIPT" --project-root="$D1" --key=QUOTED_DOUBLE)
[ "$out" = "value with spaces" ] && ok "5.1 quotes stripped" || ko "5.1 got '$out'"

# 6. single-quoted value stripped
echo ""
echo "[6] single-quoted value"
out=$(bash "$SCRIPT" --project-root="$D1" --key=QUOTED_SINGLE)
[ "$out" = "single quoted" ] && ok "6.1 single quotes stripped" || ko "6.1 got '$out'"

# 7. indented line tolerated
echo ""
echo "[7] indented line"
out=$(bash "$SCRIPT" --project-root="$D1" --key=INDENTED)
[ "$out" = "ok" ] && ok "7.1 indented parsed" || ko "7.1 got '$out'"

# 8. empty value
echo ""
echo "[8] empty value"
out=$(bash "$SCRIPT" --project-root="$D1" --key=EMPTY_VALUE)
[ "$out" = "" ] && ok "8.1 empty value" || ko "8.1 got '$out'"

# 9. missing key → exit 1
echo ""
echo "[9] missing key"
bash "$SCRIPT" --project-root="$D1" --key=NOPE >/dev/null 2>&1
[ $? -eq 1 ] && ok "9.1 exit 1 when key absent" || ko "9.1 wrong rc"

# 10. comments skipped
echo ""
echo "[10] comments skipped"
bash "$SCRIPT" --project-root="$D1" --key="# Snapship secrets — gitignored" >/dev/null 2>&1
[ $? -eq 1 ] && ok "10.1 comment line is not a key" || ko "10.1 comment leaked"

# 11. dump all (no --key)
echo ""
echo "[11] dump all"
out=$(bash "$SCRIPT" --project-root="$D1" | grep -c '=')
[ "$out" -ge 5 ] && ok "11.1 prints multiple KEY=VALUE" || ko "11.1 only $out lines"

# 12. KEY first match wins (first occurrence)
echo ""
echo "[12] first-match-wins"
D2="$TMPDIR_BASE/p2"
mkdir -p "$D2"
cat > "$D2/.env.snapship" <<'EOF'
DUP=first
DUP=second
EOF
out=$(bash "$SCRIPT" --project-root="$D2" --key=DUP)
[ "$out" = "first" ] && ok "12.1 first wins" || ko "12.1 got '$out'"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "Failures:"
  for e in "${ERRORS[@]}"; do echo "  - $e"; done
  exit 1
fi
exit 0
