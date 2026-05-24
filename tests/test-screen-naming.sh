#!/usr/bin/env bash
# Tests for skills/_shared/screen-naming.sh
# Real behaviour: real jq, real temp dirs, real load-config.sh. No mocks.
# Covers both /wireframe (wireframes.naming_pattern) and /design
# (design.naming_pattern, with the literal "-design" suffix).

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/skills/_shared/screen-naming.sh"

PASS=0
FAIL=0
ERRORS=()

ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

echo "=== screen-naming.sh tests ==="

# 1. default pattern via --pattern override (no config touched)
echo ""
echo "[1] default pattern {story_id}-{screen_name}"
out=$(bash "$SCRIPT" --pattern='{story_id}-{screen_name}' \
  --context='{"story_id":"01-login","screen_name":"signup-screen"}')
[ "$out" = "01-login-signup-screen" ] && ok "1.1 both tokens substituted" || ko "1.1 got '$out'"

# 2. extra {state} token (parity with legacy hardcoded form)
echo ""
echo "[2] {state} token"
out=$(bash "$SCRIPT" --pattern='{story_id}-{screen_name}-{state}' \
  --context='{"story_id":"01-login","screen_name":"signup-screen","state":"empty"}')
[ "$out" = "01-login-signup-screen-empty" ] && ok "2.1 state substituted" || ko "2.1 got '$out'"

# 3. custom separators / subdir
echo ""
echo "[3] custom pattern with subdir"
out=$(bash "$SCRIPT" --pattern='{story_id}/{screen_name}_{state}' \
  --context='{"story_id":"02-dash","screen_name":"dashboard","state":"filled"}')
[ "$out" = "02-dash/dashboard_filled" ] && ok "3.1 custom separators kept" || ko "3.1 got '$out'"

# 4. token repeated in pattern
echo ""
echo "[4] repeated token"
out=$(bash "$SCRIPT" --pattern='{story_id}-{story_id}' \
  --context='{"story_id":"x"}')
[ "$out" = "x-x" ] && ok "4.1 all occurrences replaced" || ko "4.1 got '$out'"

# 5. unknown token rejected
echo ""
echo "[5] unknown token fails loudly"
bash "$SCRIPT" --pattern='{story_id}-{bogus}' --context='{"story_id":"x"}' >/dev/null 2>&1
[ $? -ne 0 ] && ok "5.1 unresolved token rejected" || ko "5.1 accepted bad pattern"

# 6. missing token value → empty substitution (still well-formed)
echo ""
echo "[6] missing token value"
out=$(bash "$SCRIPT" --pattern='{story_id}-{screen_name}' --context='{"story_id":"01-x"}')
[ "$out" = "01-x-" ] && ok "6.1 absent screen_name → empty" || ko "6.1 got '$out'"

# 7. invalid JSON context rejected
echo ""
echo "[7] invalid context JSON"
bash "$SCRIPT" --pattern='{story_id}' --context='not json' >/dev/null 2>&1
[ $? -ne 0 ] && ok "7.1 invalid JSON rejected" || ko "7.1 accepted"

# 8. missing --context rejected
echo ""
echo "[8] missing --context"
bash "$SCRIPT" --pattern='{story_id}' >/dev/null 2>&1
[ $? -ne 0 ] && ok "8.1 --context required" || ko "8.1 accepted"

# 9. config-driven pattern (real load-config.sh + on-disk snap.config.json)
echo ""
echo "[9] config-driven wireframes.naming_pattern"
TMP=$(mktemp -d)
cat > "$TMP/snap.config.json" <<'EOF'
{
  "version": "1.0",
  "repository": { "platform": "github" },
  "tickets": { "platform": "inherit" },
  "documentation": { "platform": "affine" },
  "wireframes": {
    "platform": "figma",
    "export_format": "png",
    "naming_pattern": "{screen_name}__{story_id}",
    "figma": {
      "file_key": "abc123XYZ",
      "file_name": "Project Wireframes",
      "token_env": "FIGMA_ACCESS_TOKEN"
    }
  }
}
EOF
out=$(bash "$SCRIPT" \
  --context='{"story_id":"03-foo","screen_name":"bar"}' \
  --project-root="$TMP" 2>/dev/null)
[ "$out" = "bar__03-foo" ] && ok "9.1 wireframes pattern read from config" || ko "9.1 got '$out'"

# 10. config absent → built-in wireframes default
echo ""
echo "[10] default fallback when config has no naming_pattern"
TMP2=$(mktemp -d)
cat > "$TMP2/snap.config.json" <<'EOF'
{
  "version": "1.0",
  "repository": { "platform": "github" },
  "tickets": { "platform": "inherit" },
  "documentation": { "platform": "affine" },
  "wireframes": {
    "platform": "figma",
    "export_format": "png",
    "figma": {
      "file_key": "abc123XYZ",
      "file_name": "Project Wireframes",
      "token_env": "FIGMA_ACCESS_TOKEN"
    }
  }
}
EOF
out=$(bash "$SCRIPT" \
  --context='{"story_id":"04-baz","screen_name":"qux"}' \
  --project-root="$TMP2" 2>/dev/null)
[ "$out" = "04-baz-qux" ] && ok "10.1 default wireframes pattern applied" || ko "10.1 got '$out'"

trash "$TMP" "$TMP2" 2>/dev/null || true

# 11. design default pattern via --pattern override — literal "-design" suffix
echo ""
echo "[11] design default pattern with literal -design suffix"
out=$(bash "$SCRIPT" --pattern='{story_id}-{screen_name}-design' \
  --context='{"story_id":"01-login","screen_name":"signup-screen"}')
[ "$out" = "01-login-signup-screen-design" ] && ok "11.1 -design suffix kept literal" || ko "11.1 got '$out'"

# 12. design config key read via --config-key + --default
echo ""
echo "[12] config-driven design.naming_pattern via --config-key"
TMP3=$(mktemp -d)
cat > "$TMP3/snap.config.json" <<'EOF'
{
  "version": "1.0",
  "repository": { "platform": "github" },
  "tickets": { "platform": "inherit" },
  "documentation": { "platform": "affine" },
  "design": {
    "platform": "penpot",
    "export_format": "png",
    "naming_pattern": "hifi/{screen_name}-{state}"
  }
}
EOF
out=$(bash "$SCRIPT" \
  --config-key='design.naming_pattern' \
  --default='{story_id}-{screen_name}-design' \
  --context='{"story_id":"05-pay","screen_name":"checkout","state":"error"}' \
  --project-root="$TMP3" 2>/dev/null)
[ "$out" = "hifi/checkout-error" ] && ok "12.1 design pattern read from config" || ko "12.1 got '$out'"

# 13. design fallback default when design.naming_pattern absent
echo ""
echo "[13] design fallback default applied"
TMP4=$(mktemp -d)
cat > "$TMP4/snap.config.json" <<'EOF'
{
  "version": "1.0",
  "repository": { "platform": "github" },
  "tickets": { "platform": "inherit" },
  "documentation": { "platform": "affine" },
  "design": {
    "platform": "penpot",
    "export_format": "png"
  }
}
EOF
out=$(bash "$SCRIPT" \
  --config-key='design.naming_pattern' \
  --default='{story_id}-{screen_name}-design' \
  --context='{"story_id":"06-acc","screen_name":"profile"}' \
  --project-root="$TMP4" 2>/dev/null)
[ "$out" = "06-acc-profile-design" ] && ok "13.1 design default suffix applied" || ko "13.1 got '$out'"

trash "$TMP3" "$TMP4" 2>/dev/null || true

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
