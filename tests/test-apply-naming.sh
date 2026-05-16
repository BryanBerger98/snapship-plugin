#!/usr/bin/env bash
# Tests for skills/_shared/apply-naming.sh

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/skills/_shared/apply-naming.sh"

PASS=0
FAIL=0
ERRORS=()

ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

echo "=== apply-naming.sh tests ==="

# 1. story_id basic
echo ""
echo "[1] story_id basic"
out=$(bash "$SCRIPT" --type=story_id --context='{"nn":"01","name":"User Authentication"}')
[ "$out" = "01-user-authentication" ] && ok "1.1 NN-kebab" || ko "1.1 got '$out'"

# 2. story_id zero-padding
echo ""
echo "[2] story_id zero-padding"
out=$(bash "$SCRIPT" --type=story_id --context='{"nn":"7","name":"Login"}')
[ "$out" = "07-login" ] && ok "2.1 single digit padded" || ko "2.1 got '$out'"
out=$(bash "$SCRIPT" --type=story_id --context='{"nn":"42","name":"Foo"}')
[ "$out" = "42-foo" ] && ok "2.2 double digit kept" || ko "2.2 got '$out'"

# 3. story_id slug truncation
echo ""
echo "[3] story_id slug truncation"
out=$(bash "$SCRIPT" --type=story_id --context='{"nn":"01","name":"This is a very long feature name that should be truncated"}' --slug-max-length=20)
[ "${#out}" -le 23 ] && ok "3.1 length within bound (got len=${#out})" || ko "3.1 too long: '$out'"
[[ "$out" =~ ^01-[a-z0-9-]+$ ]] && ok "3.2 valid kebab" || ko "3.2 invalid: '$out'"
[[ "$out" != *- ]] && ok "3.3 no trailing dash" || ko "3.3 trailing dash: '$out'"

# 4. story_id accent fold
echo ""
echo "[4] story_id accent fold"
out=$(bash "$SCRIPT" --type=story_id --context='{"nn":"01","name":"Authéntïcâtion à français"}')
[[ "$out" =~ ^01-[a-z0-9-]+$ ]] && ok "4.1 accents folded: $out" || ko "4.1 got '$out'"

# 5. story_id special chars
echo ""
echo "[5] story_id special chars"
out=$(bash "$SCRIPT" --type=story_id --context='{"nn":"01","name":"Feature/Name (v2.0) & more!"}')
[[ "$out" =~ ^01-[a-z0-9-]+$ ]] && ok "5.1 special chars stripped: $out" || ko "5.1 got '$out'"

# 6. story_id missing nn
echo ""
echo "[6] story_id missing nn"
bash "$SCRIPT" --type=story_id --context='{"name":"x"}' >/dev/null 2>&1
[ $? -ne 0 ] && ok "6.1 nn required" || ko "6.1 accepted"

# 7. story_id non-integer nn
echo ""
echo "[7] story_id non-integer nn"
bash "$SCRIPT" --type=story_id --context='{"nn":"abc","name":"x"}' >/dev/null 2>&1
[ $? -ne 0 ] && ok "7.1 non-integer rejected" || ko "7.1 accepted"

# 8. story_id missing name
echo ""
echo "[8] story_id missing name"
bash "$SCRIPT" --type=story_id --context='{"nn":"01"}' >/dev/null 2>&1
[ $? -ne 0 ] && ok "8.1 name required" || ko "8.1 accepted"

# 9. story_id name produces empty slug
echo ""
echo "[9] story_id empty slug rejected"
bash "$SCRIPT" --type=story_id --context='{"nn":"01","name":"!!!"}' >/dev/null 2>&1
[ $? -ne 0 ] && ok "9.1 empty slug rejected" || ko "9.1 accepted"

# 10. branch default template
echo ""
echo "[10] branch default template"
out=$(bash "$SCRIPT" --type=branch \
  --context='{"type":"feat","ticket_id":"AUTH-3","slug":"login-form"}' \
  --branch-pattern='{type}/{ticket_id}-{slug}')
[ "$out" = "feat/AUTH-3-login-form" ] && ok "10.1 default rendered" || ko "10.1 got '$out'"

# 11. branch ticket id case preserved
echo ""
echo "[11] branch ticket_id case preserved"
out=$(bash "$SCRIPT" --type=branch \
  --context='{"type":"fix","ticket_id":"PROJ-123","slug":"Fix Login Bug"}' \
  --branch-pattern='{type}/{ticket_id}-{slug}')
[ "$out" = "fix/PROJ-123-fix-login-bug" ] && ok "11.1 ticket case kept, slug normalized" || ko "11.1 got '$out'"

# 12. branch custom template
echo ""
echo "[12] branch custom template"
out=$(bash "$SCRIPT" --type=branch \
  --context='{"type":"feat","ticket_id":"X-1","slug":"abc"}' \
  --branch-pattern='{ticket_id}/{type}-{slug}')
[ "$out" = "X-1/feat-abc" ] && ok "12.1 custom rendered" || ko "12.1 got '$out'"

# 13. branch missing fields
echo ""
echo "[13] branch missing fields"
bash "$SCRIPT" --type=branch --context='{"type":"feat","slug":"x"}' \
  --branch-pattern='{type}/{ticket_id}-{slug}' >/dev/null 2>&1
[ $? -ne 0 ] && ok "13.1 ticket_id required" || ko "13.1 accepted"
bash "$SCRIPT" --type=branch --context='{"ticket_id":"X-1","slug":"x"}' \
  --branch-pattern='{type}/{ticket_id}-{slug}' >/dev/null 2>&1
[ $? -ne 0 ] && ok "13.2 type required" || ko "13.2 accepted"
bash "$SCRIPT" --type=branch --context='{"type":"feat","ticket_id":"X-1"}' \
  --branch-pattern='{type}/{ticket_id}-{slug}' >/dev/null 2>&1
[ $? -ne 0 ] && ok "13.3 slug required" || ko "13.3 accepted"

# 14. commit default
echo ""
echo "[14] commit default template"
out=$(bash "$SCRIPT" --type=commit \
  --context='{"type":"feat","scope":"auth","message":"add login"}' \
  --commit-pattern='{type}({scope}): {message}')
[ "$out" = "feat(auth): add login" ] && ok "14.1 default rendered" || ko "14.1 got '$out'"

# 15. commit empty scope
echo ""
echo "[15] commit empty scope strips parens"
out=$(bash "$SCRIPT" --type=commit \
  --context='{"type":"chore","message":"bump deps"}' \
  --commit-pattern='{type}({scope}): {message}')
[ "$out" = "chore: bump deps" ] && ok "15.1 empty scope stripped" || ko "15.1 got '$out'"

# 16. commit custom template
echo ""
echo "[16] commit custom template"
out=$(bash "$SCRIPT" --type=commit \
  --context='{"type":"fix","scope":"core","message":"crash"}' \
  --commit-pattern='[{type}] {scope}: {message}')
[ "$out" = "[fix] core: crash" ] && ok "16.1 custom rendered" || ko "16.1 got '$out'"

# 17. commit missing fields
echo ""
echo "[17] commit missing fields"
bash "$SCRIPT" --type=commit --context='{"scope":"a","message":"b"}' \
  --commit-pattern='{type}({scope}): {message}' >/dev/null 2>&1
[ $? -ne 0 ] && ok "17.1 type required" || ko "17.1 accepted"
bash "$SCRIPT" --type=commit --context='{"type":"feat","scope":"a"}' \
  --commit-pattern='{type}({scope}): {message}' >/dev/null 2>&1
[ $? -ne 0 ] && ok "17.2 message required" || ko "17.2 accepted"

# 18. invalid type
echo ""
echo "[18] invalid type"
bash "$SCRIPT" --type=invalid --context='{}' >/dev/null 2>&1
[ $? -ne 0 ] && ok "18.1 invalid type rejected" || ko "18.1 accepted"

# 19. invalid JSON context
echo ""
echo "[19] invalid JSON context"
bash "$SCRIPT" --type=story_id --context='not json' >/dev/null 2>&1
[ $? -ne 0 ] && ok "19.1 invalid JSON rejected" || ko "19.1 accepted"

# 20. config-driven naming (no overrides)
echo ""
echo "[20] config-driven naming"
TMP=$(mktemp -d)
mkdir -p "$TMP/.claude/product"
cat > "$TMP/snap.config.json" <<'EOF'
{
  "version": "1.0",
  "tools": {
    "tickets": "github",
    "docs": "markdown",
    "wireframes": "ascii"
  },
  "github": {
    "repo": "x/y"
  },
  "naming": {
    "story_slug_max_length": 15,
    "branch_pattern": "{type}-{ticket_id}/{slug}",
    "commit_pattern": "{type}: {message}"
  }
}
EOF
out=$(bash "$SCRIPT" --type=story_id --context='{"nn":"01","name":"Authentication system feature"}' --project-root="$TMP" 2>/dev/null)
[ "${#out}" -le 18 ] && ok "20.1 config slug max applied (got len=${#out}: $out)" || ko "20.1 too long: '$out'"

out=$(bash "$SCRIPT" --type=branch \
  --context='{"type":"feat","ticket_id":"X-1","slug":"abc"}' \
  --project-root="$TMP" 2>/dev/null)
[ "$out" = "feat-X-1/abc" ] && ok "20.2 config branch pattern" || ko "20.2 got '$out'"

out=$(bash "$SCRIPT" --type=commit \
  --context='{"type":"feat","message":"x"}' \
  --project-root="$TMP" 2>/dev/null)
[ "$out" = "feat: x" ] && ok "20.3 config commit pattern" || ko "20.3 got '$out'"

trash "$TMP" 2>/dev/null || rm -rf "$TMP"

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
