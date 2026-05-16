#!/usr/bin/env bash
# /snap:doc-update --epic=<id> when all children done :
#   - epic story_type validated
#   - all children state in {done, closed}
#   - content payload built + hash computed
#   - section generated when hash differs from existing marker

set -uo pipefail

PASS=0
FAIL=0
ERRORS=()

ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1 — $2"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

# Mirror of step-01b-epic-ship.md logic — pure function over JSON inputs.
# Returns:
#   0 + stdout "section <hash>"   → generate section
#   0 + stdout "skip-hash <hash>" → section already published (hash match)
#   0 + stdout "skip-partial X/N" → not all children done
#   1                              → invalid input (not epic, fetch error)
epic_ship_decide() {
  local epic_json="$1" children_json="$2"
  local story_type total done_count payload hash existing
  story_type=$(jq -r '.story_type // ""' <<<"$epic_json")
  [ "$story_type" = "epic" ] || { echo "ERROR: not an epic" >&2; return 1; }

  total=$(jq '.items | length' <<<"$children_json")
  if [ "$total" -eq 0 ]; then
    echo "skip-empty"
    return 0
  fi
  done_count=$(jq '[.items[] | select(.state == "done" or .state == "closed")] | length' <<<"$children_json")
  if [ "$done_count" -lt "$total" ]; then
    printf 'skip-partial %s/%s' "$done_count" "$total"
    return 0
  fi

  payload=$(jq -nc --argjson epic "$epic_json" --argjson kids "$children_json" \
    '{epic_id:$epic.platform_id, title:$epic.title,
      business_goal:($epic.business_goal // ""),
      success_metrics:($epic.success_metrics // []),
      children:($kids.items | map({platform_id,title,url}))}')
  hash=$(printf '%s' "$payload" | sha256sum | cut -d" " -f1)

  existing=$(printf '%s' "$epic_json" | jq -r '.body // ""' \
    | grep -oE 'snap:ship-hash:[a-f0-9]+' | cut -d: -f3 | head -1)
  if [ "$existing" = "$hash" ]; then
    printf 'skip-hash %s' "$hash"
    return 0
  fi
  printf 'section %s' "$hash"
  return 0
}

echo "=== /snap:doc-update --epic all-done section ==="

# 1. Happy path — Epic with 3 done children → section generated
EPIC='{"platform_id":"#42","story_type":"epic","title":"Auth Epic","business_goal":"unlock SSO","success_metrics":["DAU +10%"],"body":""}'
CHILDREN='{"items":[
  {"platform_id":"#43","title":"Signup","url":"https://gh/43","state":"done","story_type":"user-story"},
  {"platform_id":"#44","title":"Login","url":"https://gh/44","state":"done","story_type":"user-story"},
  {"platform_id":"#45","title":"Reset password","url":"https://gh/45","state":"closed","story_type":"user-story"}
],"count":3}'
out=$(epic_ship_decide "$EPIC" "$CHILDREN")
case "$out" in
  section\ *) ok "1.1 all-done → section generated" ;;
  *) ko "1.1" "out=$out" ;;
esac

# 2. Hash is deterministic for same payload
out1=$(epic_ship_decide "$EPIC" "$CHILDREN")
out2=$(epic_ship_decide "$EPIC" "$CHILDREN")
[ "$out1" = "$out2" ] && ok "2.1 hash deterministic" || ko "2.1" "diff: $out1 vs $out2"

# 3. Different children → different hash
CHILDREN2='{"items":[
  {"platform_id":"#43","title":"Signup","url":"https://gh/43","state":"done","story_type":"user-story"},
  {"platform_id":"#44","title":"Login","url":"https://gh/44","state":"closed","story_type":"user-story"}
],"count":2}'
out3=$(epic_ship_decide "$EPIC" "$CHILDREN2")
hash1=$(echo "$out1" | awk '{print $2}')
hash3=$(echo "$out3" | awk '{print $2}')
[ "$hash1" != "$hash3" ] && ok "3.1 different children produce different hash" || ko "3.1" "same hash $hash1"

# 4. Idempotent — existing hash on body matches → skip
HASH=$(echo "$out1" | awk '{print $2}')
EPIC_STAMPED='{"platform_id":"#42","story_type":"epic","title":"Auth Epic","business_goal":"unlock SSO","success_metrics":["DAU +10%"],"body":"some prior content\n<!-- snap:ship-hash:'"$HASH"' -->"}'
out=$(epic_ship_decide "$EPIC_STAMPED" "$CHILDREN")
case "$out" in
  skip-hash\ *) ok "4.1 same hash → skip-hash" ;;
  *) ko "4.1" "out=$out" ;;
esac

# 5. Different hash on body → still generates section (re-ship after change)
EPIC_OLDHASH='{"platform_id":"#42","story_type":"epic","title":"Auth Epic","business_goal":"unlock SSO","success_metrics":["DAU +10%"],"body":"<!-- snap:ship-hash:deadbeefdeadbeef -->"}'
out=$(epic_ship_decide "$EPIC_OLDHASH" "$CHILDREN")
case "$out" in
  section\ *) ok "5.1 stale hash → section regenerated" ;;
  *) ko "5.1" "out=$out" ;;
esac

# 6. Empty children list → skip-empty
EPIC_NOCHILD='{"platform_id":"#99","story_type":"epic","title":"Empty","body":""}'
EMPTY='{"items":[],"count":0}'
out=$(epic_ship_decide "$EPIC_NOCHILD" "$EMPTY")
[ "$out" = "skip-empty" ] && ok "6.1 empty children → skip-empty" || ko "6.1" "out=$out"

# 7. Non-epic ticket rejected
US='{"platform_id":"#50","story_type":"user-story","title":"x","body":""}'
out=$(epic_ship_decide "$US" "$CHILDREN" 2>/dev/null)
rc=$?
[ "$rc" -eq 1 ] && ok "7.1 non-epic returns exit 1" || ko "7.1" "rc=$rc out=$out"

# 8. Mixed state children (only some done) → not all-done branch (covered in partial test)
# Here verify single-done out of three returns skip-partial
MIXED='{"items":[
  {"platform_id":"#43","title":"x","url":"u","state":"done"},
  {"platform_id":"#44","title":"x","url":"u","state":"in_progress"},
  {"platform_id":"#45","title":"x","url":"u","state":"todo"}
],"count":3}'
out=$(epic_ship_decide "$EPIC" "$MIXED")
case "$out" in
  "skip-partial 1/3") ok "8.1 mixed states → skip-partial 1/3" ;;
  *) ko "8.1" "out=$out" ;;
esac

echo ""
echo "=== Summary ==="
echo "Passed: ${PASS}"
echo "Failed: ${FAIL}"
[ "$FAIL" -gt 0 ] && { printf '  - %s\n' "${ERRORS[@]}"; exit 1; }
exit 0
