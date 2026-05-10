#!/usr/bin/env bash
# Tests for skills/_shared/resolve-template.sh

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/skills/_shared/resolve-template.sh"
TPL_FIXTURES="${ROOT}/tests/fixtures/valid/templates"
BUNDLED_DIR="${ROOT}/skills/_shared/templates"

PASS=0
FAIL=0
ERRORS=()

ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1 — $2"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

setup_dir() { mktemp -d -t snap-rt-XXXXXX; }

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then ok "$label"
  else ko "$label" "expected '$expected', got '$actual'"; fi
}

echo "=== resolve-template.sh tests ==="

# 1. arg validation
echo ""
echo "[1] arg validation"
bash "$SCRIPT" >/dev/null 2>&1
[ $? -eq 1 ] && ok "1.1 missing --kind exit 1" || ko "1.1" "rc=$?"

bash "$SCRIPT" --kind=foo >/dev/null 2>&1
[ $? -eq 1 ] && ok "1.2 invalid kind exit 1" || ko "1.2" "rc=$?"

bash "$SCRIPT" --kind=ticket --platform=github >/dev/null 2>&1
[ $? -eq 1 ] && ok "1.3 ticket missing --type" || ko "1.3" "rc=$?"

bash "$SCRIPT" --kind=ticket --type=user-story >/dev/null 2>&1
[ $? -eq 1 ] && ok "1.4 ticket missing --platform" || ko "1.4" "rc=$?"

bash "$SCRIPT" --kind=ticket --type=invalid --platform=github >/dev/null 2>&1
[ $? -eq 1 ] && ok "1.5 invalid type" || ko "1.5" "rc=$?"

bash "$SCRIPT" --kind=ticket --type=user-story --platform=bitbucket >/dev/null 2>&1
[ $? -eq 1 ] && ok "1.6 invalid platform for ticket" || ko "1.6" "rc=$?"

bash "$SCRIPT" --kind=pr >/dev/null 2>&1
[ $? -eq 1 ] && ok "1.7 pr missing --platform" || ko "1.7" "rc=$?"

bash "$SCRIPT" --kind=review-thread >/dev/null 2>&1
[ $? -eq 1 ] && ok "1.8 review-thread missing --platform" || ko "1.8" "rc=$?"

# 2. bundled fallback (no user override)
echo ""
echo "[2] bundled fallback"
DIR=$(setup_dir)

out=$(bash "$SCRIPT" --kind=ticket --type=user-story --platform=github --project-root="$DIR")
assert_eq "2.1 ticket user-story github" "${BUNDLED_DIR}/tickets/user-story/github.md" "$out"

out=$(bash "$SCRIPT" --kind=ticket --type=bug --platform=gitlab --project-root="$DIR")
assert_eq "2.2 ticket bug gitlab" "${BUNDLED_DIR}/tickets/bug/gitlab.md" "$out"

out=$(bash "$SCRIPT" --kind=ticket --type=epic --platform=jira --project-root="$DIR")
assert_eq "2.3 ticket epic jira" "${BUNDLED_DIR}/tickets/epic/jira.md" "$out"

out=$(bash "$SCRIPT" --kind=pr --platform=github --project-root="$DIR")
assert_eq "2.4 pr github" "${BUNDLED_DIR}/pr/github.md" "$out"

out=$(bash "$SCRIPT" --kind=pr --platform=default --project-root="$DIR")
assert_eq "2.5 pr default" "${BUNDLED_DIR}/pr/default.md" "$out"

out=$(bash "$SCRIPT" --kind=review-thread --platform=jira --project-root="$DIR")
assert_eq "2.6 review-thread jira" "${BUNDLED_DIR}/review-thread/jira.md" "$out"

out=$(bash "$SCRIPT" --kind=aggregated-feedback --project-root="$DIR")
assert_eq "2.7 aggregated-feedback" "${BUNDLED_DIR}/aggregated-feedback.md" "$out"

trash "$DIR" 2>/dev/null || true

# 3. user override (ticket)
echo ""
echo "[3] user override — ticket"
DIR=$(setup_dir)
mkdir -p "$DIR/tpl"
cp "${TPL_FIXTURES}/custom-user-story.md" "$DIR/tpl/us.md"
cp "${TPL_FIXTURES}/custom-bug.md"        "$DIR/tpl/bug.md"

cat > "$DIR/snapship.config.json" <<JSON
{
  "version": "1.0",
  "templates": {
    "tickets": {
      "user_story": "tpl/us.md",
      "bug": "tpl/bug.md"
    }
  }
}
JSON

out=$(bash "$SCRIPT" --kind=ticket --type=user-story --platform=github --project-root="$DIR")
assert_eq "3.1 user_story override (relative)" "${DIR}/tpl/us.md" "$out"

out=$(bash "$SCRIPT" --kind=ticket --type=bug --platform=gitlab --project-root="$DIR")
assert_eq "3.2 bug override" "${DIR}/tpl/bug.md" "$out"

# epic not overridden → bundled
out=$(bash "$SCRIPT" --kind=ticket --type=epic --platform=github --project-root="$DIR")
assert_eq "3.3 epic falls back to bundled" "${BUNDLED_DIR}/tickets/epic/github.md" "$out"
trash "$DIR" 2>/dev/null || true

# 4. user override — pr / review-thread / aggregated-feedback
echo ""
echo "[4] user override — pr / review-thread / aggregated-feedback"
DIR=$(setup_dir)
mkdir -p "$DIR/tpl"
cp "${TPL_FIXTURES}/custom-pr.md"                  "$DIR/tpl/pr.md"
cp "${TPL_FIXTURES}/custom-review-thread.md"       "$DIR/tpl/rt.md"
cp "${TPL_FIXTURES}/custom-aggregated-feedback.md" "$DIR/tpl/agg.md"

cat > "$DIR/snapship.config.json" <<JSON
{
  "version": "1.0",
  "templates": {
    "pr": "tpl/pr.md",
    "review_thread": "tpl/rt.md",
    "aggregated_feedback": "tpl/agg.md"
  }
}
JSON

out=$(bash "$SCRIPT" --kind=pr --platform=github --project-root="$DIR")
assert_eq "4.1 pr override (single override applies to all platforms)" "${DIR}/tpl/pr.md" "$out"

out=$(bash "$SCRIPT" --kind=pr --platform=gitlab --project-root="$DIR")
assert_eq "4.2 pr override (gitlab uses same)" "${DIR}/tpl/pr.md" "$out"

out=$(bash "$SCRIPT" --kind=review-thread --platform=github --project-root="$DIR")
assert_eq "4.3 review-thread override" "${DIR}/tpl/rt.md" "$out"

out=$(bash "$SCRIPT" --kind=aggregated-feedback --project-root="$DIR")
assert_eq "4.4 aggregated-feedback override" "${DIR}/tpl/agg.md" "$out"
trash "$DIR" 2>/dev/null || true

# 5. user override absolute path
echo ""
echo "[5] absolute path override"
DIR=$(setup_dir)
ABS_TPL="${TPL_FIXTURES}/custom-pr.md"
cat > "$DIR/snapship.config.json" <<JSON
{
  "version": "1.0",
  "templates": { "pr": "${ABS_TPL}" }
}
JSON
out=$(bash "$SCRIPT" --kind=pr --platform=github --project-root="$DIR")
assert_eq "5.1 absolute path passes through" "$ABS_TPL" "$out"
trash "$DIR" 2>/dev/null || true

# 6. user override pointing to missing file → exit 2
echo ""
echo "[6] override → missing file"
DIR=$(setup_dir)
cat > "$DIR/snapship.config.json" <<'JSON'
{
  "version": "1.0",
  "templates": { "pr": "tpl/does-not-exist.md" }
}
JSON
bash "$SCRIPT" --kind=pr --platform=github --project-root="$DIR" >/dev/null 2>&1
[ $? -eq 2 ] && ok "6.1 missing override exit 2" || ko "6.1" "rc=$?"
trash "$DIR" 2>/dev/null || true

# 7. null override (explicit) → bundled
echo ""
echo "[7] explicit null in config"
DIR=$(setup_dir)
cat > "$DIR/snapship.config.json" <<'JSON'
{
  "version": "1.0",
  "templates": {
    "tickets": { "user_story": null }
  }
}
JSON
out=$(bash "$SCRIPT" --kind=ticket --type=user-story --platform=github --project-root="$DIR")
assert_eq "7.1 null user_story → bundled" "${BUNDLED_DIR}/tickets/user-story/github.md" "$out"
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
