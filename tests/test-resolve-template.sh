#!/usr/bin/env bash
# Tests for skills/_shared/resolve-template.sh
#
# resolve-template.sh emits JSON {path, source, render_mode}.
# Resolution order: config override > repo-native (.github/.gitlab) > bundled.

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

# Run resolve-template.sh, assert the JSON fields path/source/render_mode.
assert_resolve() {
  local label="$1" exp_path="$2" exp_source="$3" exp_mode="$4"; shift 4
  local out
  if ! out=$(bash "$SCRIPT" "$@" 2>/dev/null); then
    ko "$label" "script exited non-zero"
    return
  fi
  local p s m
  p=$(printf '%s' "$out" | jq -r '.path')
  s=$(printf '%s' "$out" | jq -r '.source')
  m=$(printf '%s' "$out" | jq -r '.render_mode')
  if [ "$p" = "$exp_path" ] && [ "$s" = "$exp_source" ] && [ "$m" = "$exp_mode" ]; then
    ok "$label"
  else
    ko "$label" "got path='$p' source='$s' mode='$m'"
  fi
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

# 2. bundled fallback (no config, no repo-native templates)
echo ""
echo "[2] bundled fallback"
DIR=$(setup_dir)

assert_resolve "2.1 ticket user-story github" \
  "${BUNDLED_DIR}/tickets/user-story/github.md" "bundled" "mustache" \
  --kind=ticket --type=user-story --platform=github --project-root="$DIR"

assert_resolve "2.2 ticket bug gitlab" \
  "${BUNDLED_DIR}/tickets/bug/gitlab.md" "bundled" "mustache" \
  --kind=ticket --type=bug --platform=gitlab --project-root="$DIR"

assert_resolve "2.3 ticket epic jira" \
  "${BUNDLED_DIR}/tickets/epic/jira.md" "bundled" "mustache" \
  --kind=ticket --type=epic --platform=jira --project-root="$DIR"

assert_resolve "2.4 pr github" \
  "${BUNDLED_DIR}/pr/github.md" "bundled" "mustache" \
  --kind=pr --platform=github --project-root="$DIR"

assert_resolve "2.5 pr default" \
  "${BUNDLED_DIR}/pr/default.md" "bundled" "mustache" \
  --kind=pr --platform=default --project-root="$DIR"

assert_resolve "2.6 review-thread jira" \
  "${BUNDLED_DIR}/review-thread/jira.md" "bundled" "mustache" \
  --kind=review-thread --platform=jira --project-root="$DIR"

assert_resolve "2.7 aggregated-feedback" \
  "${BUNDLED_DIR}/aggregated-feedback.md" "bundled" "mustache" \
  --kind=aggregated-feedback --project-root="$DIR"

trash "$DIR" 2>/dev/null || true

# 3. config override (ticket)
echo ""
echo "[3] config override — ticket"
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

assert_resolve "3.1 user_story override (relative)" \
  "${DIR}/tpl/us.md" "config" "mustache" \
  --kind=ticket --type=user-story --platform=github --project-root="$DIR"

assert_resolve "3.2 bug override" \
  "${DIR}/tpl/bug.md" "config" "mustache" \
  --kind=ticket --type=bug --platform=gitlab --project-root="$DIR"

# epic not overridden → bundled
assert_resolve "3.3 epic falls back to bundled" \
  "${BUNDLED_DIR}/tickets/epic/github.md" "bundled" "mustache" \
  --kind=ticket --type=epic --platform=github --project-root="$DIR"
trash "$DIR" 2>/dev/null || true

# 4. config override — pr / review-thread / aggregated-feedback
echo ""
echo "[4] config override — pr / review-thread / aggregated-feedback"
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

assert_resolve "4.1 pr override (single override applies to all platforms)" \
  "${DIR}/tpl/pr.md" "config" "mustache" \
  --kind=pr --platform=github --project-root="$DIR"

assert_resolve "4.2 pr override (gitlab uses same)" \
  "${DIR}/tpl/pr.md" "config" "mustache" \
  --kind=pr --platform=gitlab --project-root="$DIR"

assert_resolve "4.3 review-thread override" \
  "${DIR}/tpl/rt.md" "config" "mustache" \
  --kind=review-thread --platform=github --project-root="$DIR"

assert_resolve "4.4 aggregated-feedback override" \
  "${DIR}/tpl/agg.md" "config" "mustache" \
  --kind=aggregated-feedback --project-root="$DIR"
trash "$DIR" 2>/dev/null || true

# 5. config override absolute path
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
assert_resolve "5.1 absolute path passes through" \
  "$ABS_TPL" "config" "mustache" \
  --kind=pr --platform=github --project-root="$DIR"
trash "$DIR" 2>/dev/null || true

# 6. config override pointing to missing file → exit 2
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
assert_resolve "7.1 null user_story → bundled" \
  "${BUNDLED_DIR}/tickets/user-story/github.md" "bundled" "mustache" \
  --kind=ticket --type=user-story --platform=github --project-root="$DIR"
trash "$DIR" 2>/dev/null || true

# 8. repo-native (.github / .gitlab) — no config, default use_repo_native=true
echo ""
echo "[8] repo-native templates"
DIR=$(setup_dir)
mkdir -p "$DIR/.github/ISSUE_TEMPLATE" "$DIR/.gitlab/issue_templates" \
         "$DIR/.gitlab/merge_request_templates"
printf 'bug scaffold\n'   > "$DIR/.github/ISSUE_TEMPLATE/bug_report.md"
printf 'feat scaffold\n'  > "$DIR/.github/ISSUE_TEMPLATE/feature_request.md"
printf 'yaml form\n'      > "$DIR/.github/ISSUE_TEMPLATE/config.yml"
printf 'pr scaffold\n'    > "$DIR/.github/PULL_REQUEST_TEMPLATE.md"
printf 'gl story\n'       > "$DIR/.gitlab/issue_templates/user_story.md"
printf 'gl mr\n'          > "$DIR/.gitlab/merge_request_templates/Default.md"

assert_resolve "8.1 github issue → bug_report.md" \
  "${DIR}/.github/ISSUE_TEMPLATE/bug_report.md" "repo-native" "scaffold" \
  --kind=ticket --type=bug --platform=github --project-root="$DIR"

assert_resolve "8.2 github issue → feature_request.md (user-story)" \
  "${DIR}/.github/ISSUE_TEMPLATE/feature_request.md" "repo-native" "scaffold" \
  --kind=ticket --type=user-story --platform=github --project-root="$DIR"

# no epic template among repo-native files → bundled
assert_resolve "8.3 github no epic match → bundled" \
  "${BUNDLED_DIR}/tickets/epic/github.md" "bundled" "mustache" \
  --kind=ticket --type=epic --platform=github --project-root="$DIR"

assert_resolve "8.4 github PR template" \
  "${DIR}/.github/PULL_REQUEST_TEMPLATE.md" "repo-native" "scaffold" \
  --kind=pr --platform=github --project-root="$DIR"

assert_resolve "8.5 gitlab issue template" \
  "${DIR}/.gitlab/issue_templates/user_story.md" "repo-native" "scaffold" \
  --kind=ticket --type=user-story --platform=gitlab --project-root="$DIR"

assert_resolve "8.6 gitlab MR template" \
  "${DIR}/.gitlab/merge_request_templates/Default.md" "repo-native" "scaffold" \
  --kind=pr --platform=gitlab --project-root="$DIR"

# JIRA has no repo-native convention → bundled even with .github present
assert_resolve "8.7 jira ticket never repo-native" \
  "${BUNDLED_DIR}/tickets/bug/jira.md" "bundled" "mustache" \
  --kind=ticket --type=bug --platform=jira --project-root="$DIR"

# review-thread / aggregated-feedback have no repo-native convention
assert_resolve "8.8 review-thread never repo-native" \
  "${BUNDLED_DIR}/review-thread/github.md" "bundled" "mustache" \
  --kind=review-thread --platform=github --project-root="$DIR"

assert_resolve "8.9 aggregated-feedback never repo-native" \
  "${BUNDLED_DIR}/aggregated-feedback.md" "bundled" "mustache" \
  --kind=aggregated-feedback --project-root="$DIR"
trash "$DIR" 2>/dev/null || true

# 9. precedence — config override beats repo-native
echo ""
echo "[9] precedence: config > repo-native"
DIR=$(setup_dir)
mkdir -p "$DIR/.github/ISSUE_TEMPLATE" "$DIR/tpl"
printf 'repo bug\n'    > "$DIR/.github/ISSUE_TEMPLATE/bug_report.md"
cp "${TPL_FIXTURES}/custom-bug.md" "$DIR/tpl/bug.md"
cat > "$DIR/snapship.config.json" <<'JSON'
{
  "version": "1.0",
  "templates": { "tickets": { "bug": "tpl/bug.md" } }
}
JSON
assert_resolve "9.1 config override wins over repo-native" \
  "${DIR}/tpl/bug.md" "config" "mustache" \
  --kind=ticket --type=bug --platform=github --project-root="$DIR"
trash "$DIR" 2>/dev/null || true

# 10. templates.use_repo_native=false → skip repo-native, use bundled
echo ""
echo "[10] use_repo_native=false"
DIR=$(setup_dir)
mkdir -p "$DIR/.github/ISSUE_TEMPLATE"
printf 'repo bug\n' > "$DIR/.github/ISSUE_TEMPLATE/bug_report.md"
cat > "$DIR/snapship.config.json" <<'JSON'
{
  "version": "1.0",
  "templates": { "use_repo_native": false }
}
JSON
assert_resolve "10.1 use_repo_native=false → bundled" \
  "${BUNDLED_DIR}/tickets/bug/github.md" "bundled" "mustache" \
  --kind=ticket --type=bug --platform=github --project-root="$DIR"
trash "$DIR" 2>/dev/null || true

# 11. templates.use_repo_native=true (explicit) → repo-native still applies
echo ""
echo "[11] use_repo_native=true (explicit)"
DIR=$(setup_dir)
mkdir -p "$DIR/.github/ISSUE_TEMPLATE"
printf 'repo bug\n' > "$DIR/.github/ISSUE_TEMPLATE/bug_report.md"
cat > "$DIR/snapship.config.json" <<'JSON'
{
  "version": "1.0",
  "templates": { "use_repo_native": true }
}
JSON
assert_resolve "11.1 use_repo_native=true → repo-native" \
  "${DIR}/.github/ISSUE_TEMPLATE/bug_report.md" "repo-native" "scaffold" \
  --kind=ticket --type=bug --platform=github --project-root="$DIR"
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
