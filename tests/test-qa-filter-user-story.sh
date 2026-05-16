#!/usr/bin/env bash
# /qa step-00 story_type filter for `user-story`:
#   - wireframe_check follows config flag
#   - design_check    follows config flag
#   - regression      runs normally
# Default story_type (missing field) treated as user-story.

set -uo pipefail

PASS=0
FAIL=0
ERRORS=()

ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1 — $2"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

apply_filter() {
  local ticket_json="$1" wf_cfg="$2" design_cfg="$3"
  local story_type
  story_type=$(jq -r '.story_type // "user-story"' <<<"$ticket_json")
  local wireframe_enabled="$wf_cfg" design_check_enabled="$design_cfg"
  case "$story_type" in
    epic) return 20 ;;
    task)
      wireframe_enabled=false
      design_check_enabled=false
      ;;
    bug)
      wireframe_enabled=false
      local has_visual has_wf_url
      has_visual=$(jq -r '
        (.labels // []) | map(ascii_downcase)
        | (index("visual") != null) or (index("ui-bug") != null)
      ' <<<"$ticket_json")
      has_wf_url=$(jq -r '(.wireframe_url // "") != ""' <<<"$ticket_json")
      if [ "$has_visual" = "true" ] || [ "$has_wf_url" = "true" ]; then
        design_check_enabled=true
      else
        design_check_enabled=false
      fi
      ;;
  esac
  printf 'wf=%s design=%s' "$wireframe_enabled" "$design_check_enabled"
}

echo "=== /qa story_type filter — user-story ==="

# 1. Config on, story_type explicit
US='{"platform_id":"#30","title":"Add login flow","story_type":"user-story"}'
out=$(apply_filter "$US" "true" "true")
[ "$out" = "wf=true design=true" ] \
  && ok "1.1 user-story keeps wireframe + design" || ko "1.1" "out=$out"

# 2. Config off → both off (config respected)
out=$(apply_filter "$US" "false" "false")
[ "$out" = "wf=false design=false" ] \
  && ok "2.1 user-story respects config off" || ko "2.1" "out=$out"

# 3. Mixed config: wireframe on, design off
out=$(apply_filter "$US" "true" "false")
[ "$out" = "wf=true design=false" ] \
  && ok "3.1 mixed config respected" || ko "3.1" "out=$out"

# 4. Mixed config: wireframe off, design on
out=$(apply_filter "$US" "false" "true")
[ "$out" = "wf=false design=true" ] \
  && ok "4.1 reverse mixed config respected" || ko "4.1" "out=$out"

# 5. Missing story_type field defaults to user-story
US_NOTYPE='{"platform_id":"#31","title":"Legacy ticket"}'
out=$(apply_filter "$US_NOTYPE" "true" "true")
[ "$out" = "wf=true design=true" ] \
  && ok "5.1 missing story_type defaults to user-story" || ko "5.1" "out=$out"

# 6. Visual label has no effect on user-story (config rules)
US_LBL='{"platform_id":"#32","title":"x","story_type":"user-story","labels":["visual"]}'
out=$(apply_filter "$US_LBL" "false" "false")
[ "$out" = "wf=false design=false" ] \
  && ok "6.1 visual label does not override user-story config" || ko "6.1" "out=$out"

# 7. Wireframe URL has no override effect on user-story
US_WF='{"platform_id":"#33","title":"x","story_type":"user-story","wireframe_url":"https://figma.com/x"}'
out=$(apply_filter "$US_WF" "false" "false")
[ "$out" = "wf=false design=false" ] \
  && ok "7.1 wireframe_url does not override user-story config" || ko "7.1" "out=$out"

echo ""
echo "=== Summary ==="
echo "Passed: ${PASS}"
echo "Failed: ${FAIL}"
[ "$FAIL" -gt 0 ] && { printf '  - %s\n' "${ERRORS[@]}"; exit 1; }
exit 0
