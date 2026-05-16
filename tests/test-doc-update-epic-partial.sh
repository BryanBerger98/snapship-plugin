#!/usr/bin/env bash
# /snap:doc-update --epic=<id> when children are partially done :
#   - emits "Epic X: Y/N done — waiting" message
#   - no section generation
#   - returns 0 (not an error, just deferred)

set -uo pipefail

PASS=0
FAIL=0
ERRORS=()

ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1 — $2"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

# Mirror of step-01b-epic-ship.md decision logic with skip-partial message.
epic_ship_run() {
  local epic_json="$1" children_json="$2"
  local story_type total done_count
  story_type=$(jq -r '.story_type // ""' <<<"$epic_json")
  if [ "$story_type" != "epic" ]; then
    echo "ERROR: not an epic" >&2
    return 1
  fi
  total=$(jq '.items | length' <<<"$children_json")
  if [ "$total" -eq 0 ]; then
    echo "NOTICE: Epic has no children — skip"
    return 0
  fi
  done_count=$(jq '[.items[] | select(.state == "done" or .state == "closed")] | length' <<<"$children_json")
  if [ "$done_count" -lt "$total" ]; then
    local epic_id
    epic_id=$(jq -r '.platform_id' <<<"$epic_json")
    echo "NOTICE: Epic ${epic_id}: ${done_count}/${total} US shipped — waiting completion"
    return 0
  fi
  echo "SHIP: would generate section"
  return 0
}

echo "=== /snap:doc-update --epic partial — defer ==="

EPIC='{"platform_id":"#42","story_type":"epic","title":"Auth Epic"}'

# 1. Zero done out of three → partial message
CHILDREN_NONE='{"items":[
  {"platform_id":"#43","state":"todo"},
  {"platform_id":"#44","state":"in_progress"},
  {"platform_id":"#45","state":"in_review"}
],"count":3}'
out=$(epic_ship_run "$EPIC" "$CHILDREN_NONE" 2>&1)
rc=$?
[ "$rc" -eq 0 ] && ok "1.1 partial defer returns exit 0" || ko "1.1" "rc=$rc"
echo "$out" | grep -q "0/3 US shipped" \
  && ok "1.2 message says 0/3 US shipped" || ko "1.2" "out=$out"
echo "$out" | grep -q "waiting completion" \
  && ok "1.3 message mentions waiting completion" || ko "1.3" "out=$out"
echo "$out" | grep -q "SHIP:" \
  && ko "1.4 no SHIP marker expected" "out=$out" \
  || ok "1.4 no section generation"

# 2. 1/3 done → partial
CHILDREN_1='{"items":[
  {"platform_id":"#43","state":"done"},
  {"platform_id":"#44","state":"in_progress"},
  {"platform_id":"#45","state":"todo"}
],"count":3}'
out=$(epic_ship_run "$EPIC" "$CHILDREN_1" 2>&1)
echo "$out" | grep -q "1/3 US shipped" && ok "2.1 1/3 reported" || ko "2.1" "out=$out"

# 3. 2/3 done → still partial (one short)
CHILDREN_2='{"items":[
  {"platform_id":"#43","state":"done"},
  {"platform_id":"#44","state":"closed"},
  {"platform_id":"#45","state":"in_review"}
],"count":3}'
out=$(epic_ship_run "$EPIC" "$CHILDREN_2" 2>&1)
echo "$out" | grep -q "2/3 US shipped" && ok "3.1 2/3 reported" || ko "3.1" "out=$out"

# 4. Epic id appears in message
out=$(epic_ship_run "$EPIC" "$CHILDREN_NONE" 2>&1)
echo "$out" | grep -q "Epic #42" \
  && ok "4.1 epic platform_id in message" || ko "4.1" "out=$out"

# 5. All-done crosses threshold → SHIP marker (not partial)
CHILDREN_ALL='{"items":[
  {"platform_id":"#43","state":"done"},
  {"platform_id":"#44","state":"closed"},
  {"platform_id":"#45","state":"done"}
],"count":3}'
out=$(epic_ship_run "$EPIC" "$CHILDREN_ALL" 2>&1)
echo "$out" | grep -q "SHIP:" \
  && ok "5.1 3/3 done triggers section" || ko "5.1" "out=$out"
echo "$out" | grep -q "waiting completion" \
  && ko "5.2 should not say waiting" "out=$out" \
  || ok "5.2 no partial message when all done"

# 6. "closed" state counts as done (GitHub semantics)
CHILDREN_CLOSED='{"items":[
  {"platform_id":"#43","state":"closed"},
  {"platform_id":"#44","state":"closed"}
],"count":2}'
out=$(epic_ship_run "$EPIC" "$CHILDREN_CLOSED" 2>&1)
echo "$out" | grep -q "SHIP:" \
  && ok "6.1 closed counts as done" || ko "6.1" "out=$out"

echo ""
echo "=== Summary ==="
echo "Passed: ${PASS}"
echo "Failed: ${FAIL}"
[ "$FAIL" -gt 0 ] && { printf '  - %s\n' "${ERRORS[@]}"; exit 1; }
exit 0
