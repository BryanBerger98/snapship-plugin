#!/usr/bin/env bash
# /qa step-00 story_type filter for `task`:
#   - wireframe_check disabled regardless of config
#   - design_check     disabled regardless of config
#   - regression       runs normally

set -uo pipefail

PASS=0
FAIL=0
ERRORS=()

ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1 — $2"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

# Mirror of the filter from skills/qa/step-00-init.md section 4.
apply_filter() {
  local ticket_json="$1" wf_cfg="$2" design_cfg="$3"
  local story_type
  story_type=$(jq -r '.story_type // "user-story"' <<<"$ticket_json")
  local wireframe_enabled="$wf_cfg" design_check_enabled="$design_cfg"
  case "$story_type" in
    epic)
      echo "EPIC_REFUSED" >&2
      return 20
      ;;
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

echo "=== /qa story_type filter — task ==="

TASK='{"platform_id":"#12","title":"Add endpoint","story_type":"task"}'

# 1. Config enables both, task forces off
out=$(apply_filter "$TASK" "true" "true")
[ "$out" = "wf=false design=false" ] \
  && ok "1.1 task disables wireframe + design" || ko "1.1" "out=$out"

# 2. Config disables both, task stays off (idempotent)
out=$(apply_filter "$TASK" "false" "false")
[ "$out" = "wf=false design=false" ] \
  && ok "2.1 task idempotent when already off" || ko "2.1" "out=$out"

# 3. Task with wireframe_url ignored — task is not user-facing per decision
TASK_WF='{"platform_id":"#13","title":"Setup CI","story_type":"task","wireframe_url":"https://figma.com/x"}'
out=$(apply_filter "$TASK_WF" "true" "true")
[ "$out" = "wf=false design=false" ] \
  && ok "3.1 task with wireframe_url still skipped" || ko "3.1" "out=$out"

# 4. Task with visual label ignored (rule is per story_type, not labels)
TASK_LBL='{"platform_id":"#14","title":"Update deps","story_type":"task","labels":["visual"]}'
out=$(apply_filter "$TASK_LBL" "true" "true")
[ "$out" = "wf=false design=false" ] \
  && ok "4.1 task with visual label still skipped" || ko "4.1" "out=$out"

echo ""
echo "=== Summary ==="
echo "Passed: ${PASS}"
echo "Failed: ${FAIL}"
[ "$FAIL" -gt 0 ] && { printf '  - %s\n' "${ERRORS[@]}"; exit 1; }
exit 0
