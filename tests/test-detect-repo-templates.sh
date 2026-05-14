#!/usr/bin/env bash
# Tests for skills/_shared/detect-repo-templates.sh
#
# Detects host-native (.github/.gitlab) markdown templates. Echoes the path
# on stdout, or nothing when no repo-native template matches.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/skills/_shared/detect-repo-templates.sh"

PASS=0
FAIL=0
ERRORS=()

ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1 — $2"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

setup_dir() { mktemp -d -t snap-drt-XXXXXX; }

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then ok "$label"
  else ko "$label" "expected '$expected', got '$actual'"; fi
}

# Run detect, assert stdout equals expected (empty string = no match).
assert_detect() {
  local label="$1" expected="$2"; shift 2
  local out
  if ! out=$(bash "$SCRIPT" "$@" 2>/dev/null); then
    ko "$label" "script exited non-zero"
    return
  fi
  assert_eq "$label" "$expected" "$out"
}

# Same, but compares case-insensitively. macOS filesystems are case-insensitive,
# so fixed-name templates (PULL_REQUEST_TEMPLATE.md) may resolve to either case.
assert_detect_ci() {
  local label="$1" expected="$2"; shift 2
  local out
  if ! out=$(bash "$SCRIPT" "$@" 2>/dev/null); then
    ko "$label" "script exited non-zero"
    return
  fi
  assert_eq "$label" \
    "$(printf '%s' "$expected" | tr '[:upper:]' '[:lower:]')" \
    "$(printf '%s' "$out" | tr '[:upper:]' '[:lower:]')"
}

echo "=== detect-repo-templates.sh tests ==="

# 1. arg validation
echo ""
echo "[1] arg validation"
bash "$SCRIPT" >/dev/null 2>&1
[ $? -eq 1 ] && ok "1.1 missing --kind exit 1" || ko "1.1" "rc=$?"

bash "$SCRIPT" --kind=design --platform=github >/dev/null 2>&1
[ $? -eq 1 ] && ok "1.2 invalid kind exit 1" || ko "1.2" "rc=$?"

bash "$SCRIPT" --kind=ticket --platform=github >/dev/null 2>&1
[ $? -eq 1 ] && ok "1.3 ticket missing --type" || ko "1.3" "rc=$?"

bash "$SCRIPT" --kind=ticket --type=bug >/dev/null 2>&1
[ $? -eq 1 ] && ok "1.4 ticket missing --platform" || ko "1.4" "rc=$?"

bash "$SCRIPT" --kind=ticket --type=invalid --platform=github >/dev/null 2>&1
[ $? -eq 1 ] && ok "1.5 invalid type" || ko "1.5" "rc=$?"

bash "$SCRIPT" --kind=ticket --type=bug --platform=bitbucket >/dev/null 2>&1
[ $? -eq 1 ] && ok "1.6 invalid ticket platform" || ko "1.6" "rc=$?"

bash "$SCRIPT" --kind=pr >/dev/null 2>&1
[ $? -eq 1 ] && ok "1.7 pr missing --platform" || ko "1.7" "rc=$?"

bash "$SCRIPT" --kind=pr --platform=jira >/dev/null 2>&1
[ $? -eq 1 ] && ok "1.8 pr invalid platform (jira)" || ko "1.8" "rc=$?"

# 2. empty project → no match, exit 0
echo ""
echo "[2] empty project"
DIR=$(setup_dir)
assert_detect "2.1 ticket github → empty" "" \
  --kind=ticket --type=bug --platform=github --project-root="$DIR"
assert_detect "2.2 pr github → empty" "" \
  --kind=pr --platform=github --project-root="$DIR"
trash "$DIR" 2>/dev/null || true

# 3. github issue templates — filename → type mapping
echo ""
echo "[3] github ISSUE_TEMPLATE dir"
DIR=$(setup_dir)
mkdir -p "$DIR/.github/ISSUE_TEMPLATE"
printf 'x\n' > "$DIR/.github/ISSUE_TEMPLATE/bug_report.md"
printf 'x\n' > "$DIR/.github/ISSUE_TEMPLATE/feature_request.md"
printf 'x\n' > "$DIR/.github/ISSUE_TEMPLATE/epic.md"
printf 'x\n' > "$DIR/.github/ISSUE_TEMPLATE/config.yml"
printf 'x\n' > "$DIR/.github/ISSUE_TEMPLATE/issue_form.yaml"

assert_detect "3.1 bug → bug_report.md" "$DIR/.github/ISSUE_TEMPLATE/bug_report.md" \
  --kind=ticket --type=bug --platform=github --project-root="$DIR"
assert_detect "3.2 user-story → feature_request.md" "$DIR/.github/ISSUE_TEMPLATE/feature_request.md" \
  --kind=ticket --type=user-story --platform=github --project-root="$DIR"
assert_detect "3.3 epic → epic.md" "$DIR/.github/ISSUE_TEMPLATE/epic.md" \
  --kind=ticket --type=epic --platform=github --project-root="$DIR"
trash "$DIR" 2>/dev/null || true

# 4. YAML issue forms are ignored
echo ""
echo "[4] YAML issue forms ignored"
DIR=$(setup_dir)
mkdir -p "$DIR/.github/ISSUE_TEMPLATE"
printf 'x\n' > "$DIR/.github/ISSUE_TEMPLATE/bug.yml"
printf 'x\n' > "$DIR/.github/ISSUE_TEMPLATE/bug.yaml"
assert_detect "4.1 only .yml/.yaml present → no match" "" \
  --kind=ticket --type=bug --platform=github --project-root="$DIR"
trash "$DIR" 2>/dev/null || true

# 5. legacy single-file .github/ISSUE_TEMPLATE.md → any type
echo ""
echo "[5] github legacy single-file template"
DIR=$(setup_dir)
mkdir -p "$DIR/.github"
printf 'x\n' > "$DIR/.github/ISSUE_TEMPLATE.md"
assert_detect "5.1 legacy file used for bug" "$DIR/.github/ISSUE_TEMPLATE.md" \
  --kind=ticket --type=bug --platform=github --project-root="$DIR"
assert_detect "5.2 legacy file used for epic" "$DIR/.github/ISSUE_TEMPLATE.md" \
  --kind=ticket --type=epic --platform=github --project-root="$DIR"
trash "$DIR" 2>/dev/null || true

# 6. typed dir template wins over legacy single-file
echo ""
echo "[6] typed dir beats legacy single-file"
DIR=$(setup_dir)
mkdir -p "$DIR/.github/ISSUE_TEMPLATE"
printf 'x\n' > "$DIR/.github/ISSUE_TEMPLATE.md"
printf 'x\n' > "$DIR/.github/ISSUE_TEMPLATE/bug_report.md"
assert_detect "6.1 bug → typed dir file" "$DIR/.github/ISSUE_TEMPLATE/bug_report.md" \
  --kind=ticket --type=bug --platform=github --project-root="$DIR"
# epic has no typed file → falls back to legacy
assert_detect "6.2 epic → legacy fallback" "$DIR/.github/ISSUE_TEMPLATE.md" \
  --kind=ticket --type=epic --platform=github --project-root="$DIR"
trash "$DIR" 2>/dev/null || true

# 7. gitlab issue templates
echo ""
echo "[7] gitlab issue_templates"
DIR=$(setup_dir)
mkdir -p "$DIR/.gitlab/issue_templates"
printf 'x\n' > "$DIR/.gitlab/issue_templates/Bug.md"
printf 'x\n' > "$DIR/.gitlab/issue_templates/User_Story.md"
assert_detect "7.1 bug → Bug.md" "$DIR/.gitlab/issue_templates/Bug.md" \
  --kind=ticket --type=bug --platform=gitlab --project-root="$DIR"
assert_detect "7.2 user-story → User_Story.md" "$DIR/.gitlab/issue_templates/User_Story.md" \
  --kind=ticket --type=user-story --platform=gitlab --project-root="$DIR"
assert_detect "7.3 epic no match → empty" "" \
  --kind=ticket --type=epic --platform=gitlab --project-root="$DIR"
trash "$DIR" 2>/dev/null || true

# 8. github PR template — location variants
echo ""
echo "[8] github PR template locations"
DIR=$(setup_dir)
mkdir -p "$DIR/.github"
printf 'x\n' > "$DIR/.github/PULL_REQUEST_TEMPLATE.md"
assert_detect_ci "8.1 .github/PULL_REQUEST_TEMPLATE.md" "$DIR/.github/PULL_REQUEST_TEMPLATE.md" \
  --kind=pr --platform=github --project-root="$DIR"
trash "$DIR" 2>/dev/null || true

DIR=$(setup_dir)
printf 'x\n' > "$DIR/PULL_REQUEST_TEMPLATE.md"
assert_detect_ci "8.2 root PULL_REQUEST_TEMPLATE.md" "$DIR/PULL_REQUEST_TEMPLATE.md" \
  --kind=pr --platform=github --project-root="$DIR"
trash "$DIR" 2>/dev/null || true

DIR=$(setup_dir)
mkdir -p "$DIR/docs"
printf 'x\n' > "$DIR/docs/pull_request_template.md"
assert_detect_ci "8.3 docs/ lowercase variant" "$DIR/docs/pull_request_template.md" \
  --kind=pr --platform=github --project-root="$DIR"
trash "$DIR" 2>/dev/null || true

DIR=$(setup_dir)
mkdir -p "$DIR/.github/PULL_REQUEST_TEMPLATE"
printf 'x\n' > "$DIR/.github/PULL_REQUEST_TEMPLATE/feature.md"
printf 'x\n' > "$DIR/.github/PULL_REQUEST_TEMPLATE/default.md"
assert_detect "8.4 dir form prefers default.md" "$DIR/.github/PULL_REQUEST_TEMPLATE/default.md" \
  --kind=pr --platform=github --project-root="$DIR"
trash "$DIR" 2>/dev/null || true

# 9. gitlab MR template
echo ""
echo "[9] gitlab merge_request_templates"
DIR=$(setup_dir)
mkdir -p "$DIR/.gitlab/merge_request_templates"
printf 'x\n' > "$DIR/.gitlab/merge_request_templates/Feature.md"
printf 'x\n' > "$DIR/.gitlab/merge_request_templates/Default.md"
assert_detect "9.1 MR dir prefers Default.md" "$DIR/.gitlab/merge_request_templates/Default.md" \
  --kind=pr --platform=gitlab --project-root="$DIR"
trash "$DIR" 2>/dev/null || true

DIR=$(setup_dir)
mkdir -p "$DIR/.gitlab/merge_request_templates"
printf 'x\n' > "$DIR/.gitlab/merge_request_templates/Only.md"
assert_detect "9.2 MR dir single file" "$DIR/.gitlab/merge_request_templates/Only.md" \
  --kind=pr --platform=gitlab --project-root="$DIR"
trash "$DIR" 2>/dev/null || true

# 10. JIRA ticket → always empty (no repo-native convention)
echo ""
echo "[10] jira has no repo-native convention"
DIR=$(setup_dir)
mkdir -p "$DIR/.github/ISSUE_TEMPLATE"
printf 'x\n' > "$DIR/.github/ISSUE_TEMPLATE/bug_report.md"
assert_detect "10.1 jira ticket → empty even with .github present" "" \
  --kind=ticket --type=bug --platform=jira --project-root="$DIR"
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
