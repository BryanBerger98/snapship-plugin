#!/usr/bin/env bash
# /develop step-99 post-merge — Jira capability gate.
# Jira has supports_epic_auto_close=true. Step-99 proceeds to close-epic via
# MCP descriptor (Jira/Linear are MCP-routed in the adapter).

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADAPTER="${ROOT}/skills/_shared/tickets-adapter.sh"

PASS=0
FAIL=0
ERRORS=()

ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1 — $2"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

DIR=$(mktemp -d -t snap-dev-eac-jira-XXXXXX)
trap 'trash "$DIR" 2>/dev/null || true' EXIT

echo "=== /develop step-99 Epic auto-close — Jira ==="

# Probe live capabilities (static matrix, no network).
caps=$(bash "$ADAPTER" --action=capabilities --platform=jira --project-root="$DIR")
[ "$(jq -r '.ok' <<<"$caps")" = "true" ] && ok "ji.1 capabilities call ok" \
  || ko "ji.1" "$caps"

supported=$(jq -r '.result.supports_epic_auto_close // false' <<<"$caps")
[ "$supported" = "true" ] && ok "ji.2 Jira supports_epic_auto_close=true" \
  || ko "ji.2" "supported=$supported"

# step-99 capability gate.
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

# Jira with parent Epic → proceed.
out=$(post_merge_gate jira "AUTH-1")
[ "$out" = "proceed:close-epic" ] \
  && ok "ji.3 step-99 gate proceeds on Jira" \
  || ko "ji.3" "out=$out"

# Adapter close-epic on Jira routes via MCP — adapter emits an MCP descriptor
# (Jira/Linear are mcp-routed). The descriptor exit is non-zero by design so
# the orchestrator picks it up. Verify the response is shaped as a descriptor.
mcp_out=$(bash "$ADAPTER" --action=close-epic --platform=jira \
  --ticket-id="AUTH-1" --project-root="$DIR" 2>&1 || true)
[[ "$mcp_out" == *"\"close-epic\""* || "$mcp_out" == *"close-epic"* ]] \
  && ok "ji.4 adapter emits close-epic intent for Jira" \
  || ko "ji.4" "$mcp_out"

# Linear shares the same matrix (supports_epic_auto_close=true) — sanity.
caps_ln=$(bash "$ADAPTER" --action=capabilities --platform=linear --project-root="$DIR")
[ "$(jq -r '.result.supports_epic_auto_close' <<<"$caps_ln")" = "true" ] \
  && ok "ln.1 Linear also supports_epic_auto_close=true" \
  || ko "ln.1" "$(jq -r '.result.supports_epic_auto_close' <<<"$caps_ln")"

echo ""
echo "=== Summary ==="
echo "Passed: ${PASS}"
echo "Failed: ${FAIL}"
[ "$FAIL" -gt 0 ] && { printf '  - %s\n' "${ERRORS[@]}"; exit 1; }
exit 0
