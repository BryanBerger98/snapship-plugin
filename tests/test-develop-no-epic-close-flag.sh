#!/usr/bin/env bash
# /develop step-99 post-merge — --no-epic-close flag (and NO_EPIC_CLOSE env)
# short-circuits BEFORE the capability probe, regardless of platform support.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADAPTER="${ROOT}/skills/_shared/tickets-adapter.sh"

PASS=0
FAIL=0
ERRORS=()

ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1 — $2"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

DIR=$(mktemp -d -t snap-dev-noec-XXXXXX)
trap 'trash "$DIR" 2>/dev/null || true' EXIT

echo "=== /develop step-99 --no-epic-close opt-out ==="

# step-99 gate with opt-out short-circuit ahead of capability probe.
post_merge_gate() {
  local platform="$1" parent_epic_id="$2" no_close="${3:-false}"
  local caps_resp supported
  [ -z "$parent_epic_id" ] && { echo "skip:no-parent-epic"; return 0; }
  [ "$no_close" = "true" ] && { echo "skip:opt-out"; return 0; }

  caps_resp=$(bash "$ADAPTER" --action=capabilities --platform="$platform" \
              --project-root="$DIR")
  supported=$(jq -r '.result.supports_epic_auto_close // false' <<<"$caps_resp")
  if [ "$supported" != "true" ]; then
    echo "skip:capability-missing"
  else
    echo "proceed:close-epic"
  fi
}

# Jira (capability=true) + parent + --no-epic-close → opt-out wins.
out=$(post_merge_gate jira "AUTH-1" "true")
[ "$out" = "skip:opt-out" ] \
  && ok "jira.1 opt-out short-circuits Jira (capability=true)" \
  || ko "jira.1" "out=$out"

# GitLab (capability=true) + parent + --no-epic-close → opt-out wins.
out=$(post_merge_gate gitlab "&42" "true")
[ "$out" = "skip:opt-out" ] \
  && ok "gl.1 opt-out short-circuits GitLab (capability=true)" \
  || ko "gl.1" "out=$out"

# GitHub (capability=false) + parent + --no-epic-close → still opt-out
# (consistent with step-99 ordering : opt-out evaluated BEFORE capability).
out=$(post_merge_gate github "#10" "true")
[ "$out" = "skip:opt-out" ] \
  && ok "gh.1 opt-out short-circuits ahead of capability probe" \
  || ko "gh.1" "out=$out"

# Same Jira + parent, opt-out=false → must proceed (sanity).
out=$(post_merge_gate jira "AUTH-1" "false")
[ "$out" = "proceed:close-epic" ] \
  && ok "jira.2 without opt-out, Jira gate proceeds" \
  || ko "jira.2" "out=$out"

# NO_EPIC_CLOSE env var path (step-99 honours both flag and env).
NO_EPIC_CLOSE=true
out=$(post_merge_gate jira "AUTH-1" "${NO_EPIC_CLOSE:-false}")
[ "$out" = "skip:opt-out" ] \
  && ok "env.1 NO_EPIC_CLOSE=true env honoured as opt-out" \
  || ko "env.1" "out=$out"

echo ""
echo "=== Summary ==="
echo "Passed: ${PASS}"
echo "Failed: ${FAIL}"
[ "$FAIL" -gt 0 ] && { printf '  - %s\n' "${ERRORS[@]}"; exit 1; }
exit 0
