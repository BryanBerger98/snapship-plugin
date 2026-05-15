#!/usr/bin/env bash
# Tests for skills/_shared/load-config.sh
# Usage: bash tests/test-load-config.sh
# Exit 0 = all pass, 1 = any fail

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/skills/_shared/load-config.sh"
FIXTURES="${ROOT}/tests/fixtures/valid/config"
INVALID="${ROOT}/tests/fixtures/invalid/config"

PASS=0
FAIL=0
ERRORS=()

setup_dir() {
  local dir
  dir="$(mktemp -d -t snap-loadcfg-XXXXXX)"
  echo "$dir"
}

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS  ${label}"
    PASS=$((PASS + 1))
  else
    echo "  FAIL  ${label}"
    echo "        expected: ${expected}"
    echo "        actual:   ${actual}"
    FAIL=$((FAIL + 1))
    ERRORS+=("${label}: expected '${expected}', got '${actual}'")
  fi
}

assert_exit() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" -eq "$actual" ]; then
    echo "  PASS  ${label}"
    PASS=$((PASS + 1))
  else
    echo "  FAIL  ${label} (exit ${actual}, expected ${expected})"
    FAIL=$((FAIL + 1))
    ERRORS+=("${label}: exit code ${actual} != ${expected}")
  fi
}

echo "=== load-config.sh tests ==="

# 1. No config file → defaults
echo ""
echo "[1] No config file → defaults"
DIR=$(setup_dir)
out=$(bash "$SCRIPT" --project-root="$DIR" 2>/dev/null)
assert_eq "1.1 default lang" "fr" "$(echo "$out" | jq -r '.defaults.lang')"
assert_eq "1.2 default review_cycles_max" "3" "$(echo "$out" | jq -r '.develop.review_cycles_max')"
assert_eq "1.3 default security threshold" "info" "$(echo "$out" | jq -r '.develop.reviews.security.severity_threshold')"
assert_eq "1.4 default fail_strategy" "next-ticket" "$(echo "$out" | jq -r '.develop.fail_strategy')"
trash "$DIR" 2>/dev/null || true

# 2. Minimal config → defaults merged
echo ""
echo "[2] Minimal config (version only)"
DIR=$(setup_dir)
cp "${FIXTURES}/minimal.json" "${DIR}/snapship.config.json"
out=$(bash "$SCRIPT" --project-root="$DIR" 2>/dev/null)
assert_eq "2.1 version" "1.0" "$(echo "$out" | jq -r '.version')"
assert_eq "2.2 default qa_cycles_max" "2" "$(echo "$out" | jq -r '.qa.qa_cycles_max')"
assert_eq "2.3 default ticket_id_regex (no platform → JIRA pattern)" "[A-Z]+-[0-9]+" "$(echo "$out" | jq -r '.naming.ticket_id_regex')"
trash "$DIR" 2>/dev/null || true

# 3. github-only → inherit resolved + ticket_id_regex by platform + user overrides
echo ""
echo "[3] github-only fixture (inherit, user overrides)"
DIR=$(setup_dir)
cp "${FIXTURES}/github-only.json" "${DIR}/snapship.config.json"
out=$(bash "$SCRIPT" --project-root="$DIR" 2>/dev/null)
assert_eq "3.1 inherit resolved → github" "github" "$(echo "$out" | jq -r '.tickets.platform')"
assert_eq "3.2 ticket_id_regex github" "#[0-9]+" "$(echo "$out" | jq -r '.naming.ticket_id_regex')"
assert_eq "3.3 lang user override" "en" "$(echo "$out" | jq -r '.defaults.lang')"
assert_eq "3.4 review_cycles_max user override" "1" "$(echo "$out" | jq -r '.develop.review_cycles_max')"
assert_eq "3.5 fail_strategy user override" "stop" "$(echo "$out" | jq -r '.develop.fail_strategy')"
assert_eq "3.6 protected_branches default" "main" "$(echo "$out" | jq -r '.repository.protected_branches[0]')"
assert_eq "3.7 security threshold (default merged)" "info" "$(echo "$out" | jq -r '.develop.reviews.security.severity_threshold')"
trash "$DIR" 2>/dev/null || true

# 4. full-jira → respects user values
echo ""
echo "[4] full-jira fixture"
DIR=$(setup_dir)
cp "${FIXTURES}/full-jira.json" "${DIR}/snapship.config.json"
out=$(bash "$SCRIPT" --project-root="$DIR" 2>/dev/null)
assert_eq "4.1 jira platform" "jira" "$(echo "$out" | jq -r '.tickets.platform')"
assert_eq "4.2 jira project_key" "PROJ" "$(echo "$out" | jq -r '.tickets.jira.project_key')"
assert_eq "4.3 wireframe_check enabled (user)" "true" "$(echo "$out" | jq -r '.qa.wireframe_check.enabled')"
assert_eq "4.4 protected_branches user list" "develop" "$(echo "$out" | jq -r '.repository.protected_branches[1]')"
trash "$DIR" 2>/dev/null || true

# 5. Invalid config → exit 1 (schema)
echo ""
echo "[5] Invalid config rejected"
DIR=$(setup_dir)
cp "${INVALID}/bad-platform.json" "${DIR}/snapship.config.json"
bash "$SCRIPT" --project-root="$DIR" >/dev/null 2>&1
assert_exit "5.1 bad-platform exit 1" 1 $?

cp "${INVALID}/extra-field.json" "${DIR}/snapship.config.json"
bash "$SCRIPT" --project-root="$DIR" >/dev/null 2>&1
assert_exit "5.2 extra-field exit 1" 1 $?
trash "$DIR" 2>/dev/null || true

# 6. Bad version → exit 2
echo ""
echo "[6] Unsupported version"
DIR=$(setup_dir)
echo '{"version":"2.0"}' > "${DIR}/snapship.config.json"
bash "$SCRIPT" --project-root="$DIR" --no-validate >/dev/null 2>&1
assert_exit "6.1 version 2.0 exit 2" 2 $?
trash "$DIR" 2>/dev/null || true

# 7. inherit without repository → exit 1
echo ""
echo "[7] inherit without repository"
DIR=$(setup_dir)
echo '{"version":"1.0","tickets":{"platform":"inherit"}}' > "${DIR}/snapship.config.json"
bash "$SCRIPT" --project-root="$DIR" --no-validate >/dev/null 2>&1
assert_exit "7.1 unresolved inherit exit 1" 1 $?
trash "$DIR" 2>/dev/null || true

# 8. Stdout: 2nd call returns same resolved config
echo ""
echo "[8] Stdout determinism (no cache file in v1.0.0)"
DIR=$(setup_dir)
cp "${FIXTURES}/full-jira.json" "${DIR}/snapship.config.json"
out1=$(bash "$SCRIPT" --project-root="$DIR" 2>/dev/null)
if [ ! -f "${DIR}/.snap/.config-resolved.json" ]; then
  echo "  PASS  8.1 no cache file written (v1.0.0 stdout-only)"
  PASS=$((PASS + 1))
else
  echo "  FAIL  8.1 unexpected cache file present"
  FAIL=$((FAIL + 1))
  ERRORS+=("8.1: cache file should not be written in v1.0.0")
fi
out2=$(bash "$SCRIPT" --project-root="$DIR" --no-validate 2>/dev/null)
assert_eq "8.2 deterministic output" "jira" "$(echo "$out2" | jq -r '.tickets.platform')"
trash "$DIR" 2>/dev/null || true

# 9. Warning: tickets.jira on non-jira platform
echo ""
echo "[9] Warning: tickets.jira on non-jira platform"
DIR=$(setup_dir)
cat > "${DIR}/snapship.config.json" <<'EOF'
{
  "version": "1.0",
  "tickets": {
    "platform": "github",
    "jira": { "project_key": "PROJ" }
  }
}
EOF
stderr=$(bash "$SCRIPT" --project-root="$DIR" --no-validate 2>&1 >/dev/null)
if echo "$stderr" | grep -q "tickets.jira section ignored"; then
  echo "  PASS  9.1 warns on dangling jira section"
  PASS=$((PASS + 1))
else
  echo "  FAIL  9.1 missing warning"
  FAIL=$((FAIL + 1))
  ERRORS+=("9.1: expected jira-ignored warning, got: ${stderr}")
fi
trash "$DIR" 2>/dev/null || true

# 10. v0.2 — documentation.paths defaults injected when platform != none
echo ""
echo "[10] v0.2 documentation paths defaults"
DIR=$(setup_dir)
cat > "${DIR}/snapship.config.json" <<'EOF'
{
  "version": "1.0",
  "documentation": { "platform": "affine", "workspace": { "id": "ws-1" } }
}
EOF
out=$(bash "$SCRIPT" --project-root="$DIR" --no-validate 2>/dev/null)
assert_eq "10.1 functional_root default" "Product Docs" "$(echo "$out" | jq -r '.documentation.paths.functional_root')"
assert_eq "10.2 prd_root default" "Change Requests" "$(echo "$out" | jq -r '.documentation.paths.prd_root')"
assert_eq "10.3 auto_update_mode default" "diff" "$(echo "$out" | jq -r '.documentation.auto_update_mode')"
assert_eq "10.4 auto_update_on_qa_success default" "true" "$(echo "$out" | jq -r '.documentation.auto_update_on_qa_success')"
trash "$DIR" 2>/dev/null || true

# 11. v0.2 — paths defaults NOT injected when platform = none
echo ""
echo "[11] v0.2 paths skip when platform=none"
DIR=$(setup_dir)
cat > "${DIR}/snapship.config.json" <<'EOF'
{
  "version": "1.0",
  "documentation": { "platform": "none" }
}
EOF
out=$(bash "$SCRIPT" --project-root="$DIR" --no-validate 2>/dev/null)
fr=$(echo "$out" | jq -r '.documentation.paths.functional_root // "<absent>"')
assert_eq "11.1 functional_root absent" "<absent>" "$fr"
auto=$(echo "$out" | jq -r '.documentation.auto_update_on_qa_success // "<absent>"')
assert_eq "11.2 auto_update absent" "<absent>" "$auto"
trash "$DIR" 2>/dev/null || true

# 12. v0.2 — user-provided paths preserved (no override)
echo ""
echo "[12] v0.2 user paths preserved"
DIR=$(setup_dir)
cat > "${DIR}/snapship.config.json" <<'EOF'
{
  "version": "1.0",
  "documentation": {
    "platform": "notion",
    "workspace": { "id": "ws-1" },
    "paths": { "functional_root": "Specs", "prd_root": "PRDs" },
    "auto_update_mode": "rewrite",
    "auto_update_on_qa_success": false
  }
}
EOF
out=$(bash "$SCRIPT" --project-root="$DIR" --no-validate 2>/dev/null)
assert_eq "12.1 functional_root user" "Specs" "$(echo "$out" | jq -r '.documentation.paths.functional_root')"
assert_eq "12.2 prd_root user" "PRDs" "$(echo "$out" | jq -r '.documentation.paths.prd_root')"
assert_eq "12.3 auto_update_mode user" "rewrite" "$(echo "$out" | jq -r '.documentation.auto_update_mode')"
assert_eq "12.4 auto_update_on_qa_success user" "false" "$(echo "$out" | jq -r '.documentation.auto_update_on_qa_success')"
trash "$DIR" 2>/dev/null || true

# 13. templates defaults — null when not set
echo ""
echo "[13] templates defaults injection"
DIR=$(setup_dir)
cp "${FIXTURES}/minimal.json" "${DIR}/snapship.config.json"
out=$(bash "$SCRIPT" --project-root="$DIR" 2>/dev/null)
assert_eq "13.1 templates.tickets.user_story default null" "null" "$(echo "$out" | jq '.templates.tickets.user_story')"
assert_eq "13.2 templates.tickets.bug default null"        "null" "$(echo "$out" | jq '.templates.tickets.bug')"
assert_eq "13.3 templates.tickets.epic default null"       "null" "$(echo "$out" | jq '.templates.tickets.epic')"
assert_eq "13.4 templates.pr default null"                 "null" "$(echo "$out" | jq '.templates.pr')"
assert_eq "13.5 templates.review_thread default null"      "null" "$(echo "$out" | jq '.templates.review_thread')"
assert_eq "13.6 templates.aggregated_feedback default null" "null" "$(echo "$out" | jq '.templates.aggregated_feedback')"
trash "$DIR" 2>/dev/null || true

# 14. templates user override preserved
echo ""
echo "[14] templates user override preserved"
DIR=$(setup_dir)
cat > "${DIR}/snapship.config.json" <<'EOF'
{
  "version": "1.0",
  "templates": {
    "tickets": { "user_story": "custom/us.md", "bug": "custom/bug.md" },
    "pr": "custom/pr.md"
  }
}
EOF
out=$(bash "$SCRIPT" --project-root="$DIR" --no-validate 2>/dev/null)
assert_eq "14.1 user_story override"   "custom/us.md"  "$(echo "$out" | jq -r '.templates.tickets.user_story')"
assert_eq "14.2 bug override"          "custom/bug.md" "$(echo "$out" | jq -r '.templates.tickets.bug')"
assert_eq "14.3 epic still null"       "null"          "$(echo "$out" | jq '.templates.tickets.epic')"
assert_eq "14.4 pr override"           "custom/pr.md"  "$(echo "$out" | jq -r '.templates.pr')"
assert_eq "14.5 review_thread null"    "null"          "$(echo "$out" | jq '.templates.review_thread')"
trash "$DIR" 2>/dev/null || true

# 15. invalid templates → schema rejection
echo ""
echo "[15] invalid templates rejected"
DIR=$(setup_dir)
cp "${INVALID}/bad-templates.json" "${DIR}/snapship.config.json"
bash "$SCRIPT" --project-root="$DIR" >/dev/null 2>&1
assert_exit "15.1 bad-templates exit 1" 1 $?
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
