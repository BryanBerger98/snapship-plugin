#!/usr/bin/env bash
# /develop step-99 post-merge — GitHub capability gate.
# GH has supports_epic_auto_close=false → step-99 skips silently without
# invoking close-epic, never blocking the run.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADAPTER="${ROOT}/skills/_shared/tickets-adapter.sh"

PASS=0
FAIL=0
ERRORS=()

ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1 — $2"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

DIR=$(mktemp -d -t snap-dev-eac-gh-XXXXXX)
trap 'trash "$DIR" 2>/dev/null || true' EXIT

echo "=== /develop step-99 Epic auto-close — GitHub ==="

# Probe live capabilities from adapter (no network — static matrix).
caps=$(bash "$ADAPTER" --action=capabilities --platform=github --project-root="$DIR")
[ "$(jq -r '.ok' <<<"$caps")" = "true" ] && ok "gh.1 capabilities call ok" \
  || ko "gh.1" "$caps"

supported=$(jq -r '.result.supports_epic_auto_close // false' <<<"$caps")
[ "$supported" = "false" ] && ok "gh.2 GH supports_epic_auto_close=false" \
  || ko "gh.2" "supported=$supported"

# step-99 capability gate (mirrors step-99-post-merge.md section C).
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
    return 0
  fi

  echo "proceed:close-epic"
  return 0
}

# GH with parent Epic → skip via capability gate.
out=$(post_merge_gate github "#10")
[ "$out" = "skip:capability-missing" ] \
  && ok "gh.3 step-99 gate skips on capability=false" \
  || ko "gh.3" "out=$out"

# GH without parent Epic → skip via no-parent branch (orthogonal sanity).
out=$(post_merge_gate github "")
[ "$out" = "skip:no-parent-epic" ] \
  && ok "gh.4 step-99 gate skips when no parent_epic_id" \
  || ko "gh.4" "out=$out"

echo ""
echo "=== Summary ==="
echo "Passed: ${PASS}"
echo "Failed: ${FAIL}"
[ "$FAIL" -gt 0 ] && { printf '  - %s\n' "${ERRORS[@]}"; exit 1; }
exit 0
