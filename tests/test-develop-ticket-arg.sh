#!/usr/bin/env bash
# /develop --ticket=<platform_id> argument validation per platform regex.
# Verifies the contract from step-00-init.md section 1.

set -uo pipefail

PASS=0
FAIL=0
ERRORS=()

ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1 — $2"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

# Mirror of the per-platform regex contract in step-00-init.md.
validate_ticket_id() {
  local platform="$1" id="$2"
  case "$platform" in
    github|gitlab) [[ "$id" =~ ^#?[0-9]+$ ]] ;;
    jira|linear)   [[ "$id" =~ ^[A-Z][A-Z0-9_]+-[0-9]+$ ]] ;;
    *) return 1 ;;
  esac
}

echo "=== /develop --ticket arg validation ==="

# GitHub : #42 and 42 accepted, AUTH-12 rejected.
validate_ticket_id github "#42" && ok "gh.1 accepts #42" || ko "gh.1" "rejected"
validate_ticket_id github "42"  && ok "gh.2 accepts 42"  || ko "gh.2" "rejected"
validate_ticket_id github "AUTH-12" && ko "gh.3" "wrongly accepted AUTH-12" \
  || ok "gh.3 rejects AUTH-12"
validate_ticket_id github "" && ko "gh.4" "wrongly accepted empty" \
  || ok "gh.4 rejects empty"

# GitLab : same shape as GitHub.
validate_ticket_id gitlab "#1234" && ok "gl.1 accepts #1234" || ko "gl.1" "rejected"
validate_ticket_id gitlab "abc"   && ko "gl.2" "wrongly accepted alpha" \
  || ok "gl.2 rejects alpha"

# Jira : PROJ-123, ENG-42 accepted, #42 rejected, lowercase rejected.
validate_ticket_id jira "AUTH-12" && ok "ji.1 accepts AUTH-12" || ko "ji.1" "rejected"
validate_ticket_id jira "PROJ-9999" && ok "ji.2 accepts PROJ-9999" || ko "ji.2" "rejected"
validate_ticket_id jira "#42" && ko "ji.3" "wrongly accepted #42" \
  || ok "ji.3 rejects #42"
validate_ticket_id jira "auth-12" && ko "ji.4" "wrongly accepted lowercase" \
  || ok "ji.4 rejects lowercase"

# Linear : same as Jira.
validate_ticket_id linear "ENG-42" && ok "li.1 accepts ENG-42" || ko "li.1" "rejected"
validate_ticket_id linear "ENG_42" && ko "li.2" "wrongly accepted underscore-only" \
  || ok "li.2 rejects ENG_42"

# Unknown platform → rejected.
validate_ticket_id unknown "#42" && ko "unk.1" "wrongly accepted on unknown platform" \
  || ok "unk.1 rejects unknown platform"

echo ""
echo "=== Summary ==="
echo "Passed: ${PASS}"
echo "Failed: ${FAIL}"
[ "$FAIL" -gt 0 ] && { printf '  - %s\n' "${ERRORS[@]}"; exit 1; }
exit 0
