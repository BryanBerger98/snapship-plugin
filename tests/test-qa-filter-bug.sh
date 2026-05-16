#!/usr/bin/env bash
# /qa step-00 story_type filter for `bug`:
#   - wireframe_check disabled (regression scope = code)
#   - design_check    conditional on label visual / ui-bug OR wireframe_url
#   - regression      runs normally

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

echo "=== /qa story_type filter — bug ==="

# 1. Plain bug, no visual label, no wireframe → both UI checks off
BUG_PLAIN='{"platform_id":"#20","title":"Fix crash on load","story_type":"bug"}'
out=$(apply_filter "$BUG_PLAIN" "true" "true")
[ "$out" = "wf=false design=false" ] \
  && ok "1.1 plain bug disables both UI checks" || ko "1.1" "out=$out"

# 2. Bug with label "visual" → design kept, wireframe still off
BUG_VISUAL='{"platform_id":"#21","title":"Modal misaligned","story_type":"bug","labels":["visual","p1"]}'
out=$(apply_filter "$BUG_VISUAL" "true" "true")
[ "$out" = "wf=false design=true" ] \
  && ok "2.1 visual bug keeps design_check" || ko "2.1" "out=$out"

# 3. Bug with label "ui-bug" (alias) → same as visual
BUG_UI='{"platform_id":"#22","title":"Button overlap","story_type":"bug","labels":["ui-bug"]}'
out=$(apply_filter "$BUG_UI" "true" "true")
[ "$out" = "wf=false design=true" ] \
  && ok "3.1 ui-bug label keeps design_check" || ko "3.1" "out=$out"

# 4. Bug with wireframe_url (no label) → design kept
BUG_WF='{"platform_id":"#23","title":"Logo cropped","story_type":"bug","wireframe_url":"https://figma.com/x"}'
out=$(apply_filter "$BUG_WF" "true" "true")
[ "$out" = "wf=false design=true" ] \
  && ok "4.1 wireframe_url on bug keeps design_check" || ko "4.1" "out=$out"

# 5. Case insensitive label match
BUG_UPPER='{"platform_id":"#24","title":"x","story_type":"bug","labels":["VISUAL"]}'
out=$(apply_filter "$BUG_UPPER" "true" "true")
[ "$out" = "wf=false design=true" ] \
  && ok "5.1 case-insensitive label match" || ko "5.1" "out=$out"

# 6. Unrelated label → design off
BUG_OTHER='{"platform_id":"#25","title":"x","story_type":"bug","labels":["backend","p2"]}'
out=$(apply_filter "$BUG_OTHER" "true" "true")
[ "$out" = "wf=false design=false" ] \
  && ok "6.1 unrelated labels do not trigger design_check" || ko "6.1" "out=$out"

# 7. Wireframe off in config, but bug still keeps design override
BUG_CFGOFF='{"platform_id":"#26","title":"x","story_type":"bug","labels":["visual"]}'
out=$(apply_filter "$BUG_CFGOFF" "false" "false")
[ "$out" = "wf=false design=true" ] \
  && ok "7.1 visual label overrides design config=off" || ko "7.1" "out=$out"

echo ""
echo "=== Summary ==="
echo "Passed: ${PASS}"
echo "Failed: ${FAIL}"
[ "$FAIL" -gt 0 ] && { printf '  - %s\n' "${ERRORS[@]}"; exit 1; }
exit 0
