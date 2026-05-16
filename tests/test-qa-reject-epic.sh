#!/usr/bin/env bash
# /qa step-00 double-safety: Epic ticket rejected with exit 20.
# /develop already refuses Epic at step-01 ; /qa enforces again.

set -uo pipefail

PASS=0
FAIL=0
ERRORS=()

ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1 — $2"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

# Mirror of the filter from skills/qa/step-00-init.md section 4.
# Returns 20 for Epic, with explicit hint on stderr.
apply_filter() {
  local ticket_json="$1" wf_cfg="$2" design_cfg="$3"
  local story_type
  story_type=$(jq -r '.story_type // "user-story"' <<<"$ticket_json")
  local wireframe_enabled="$wf_cfg" design_check_enabled="$design_cfg"
  case "$story_type" in
    epic)
      echo "ERROR: /qa cannot validate an Epic — Epics aggregate child US/Task." >&2
      echo "       Hint: run /qa --ticket=<child-id> on each child instead." >&2
      return 20
      ;;
    task)
      wireframe_enabled=false
      design_check_enabled=false
      ;;
    bug)
      wireframe_enabled=false
      ;;
  esac
  printf 'wf=%s design=%s' "$wireframe_enabled" "$design_check_enabled"
}

echo "=== /qa reject epic — double-safety ==="

# 1. Epic ticket → exit 20
EPIC='{"platform_id":"#100","title":"Auth Epic","story_type":"epic"}'
out=$(apply_filter "$EPIC" "true" "true" 2>/dev/null)
rc=$?
[ "$rc" -eq 20 ] && ok "1.1 epic returns exit 20" || ko "1.1" "rc=$rc"
[ -z "$out" ] && ok "1.2 epic emits no stdout payload" || ko "1.2" "out=$out"

# 2. Epic emits explicit error message on stderr
stderr=$(apply_filter "$EPIC" "true" "true" 2>&1 >/dev/null)
echo "$stderr" | grep -q "cannot validate an Epic" \
  && ok "2.1 stderr explains refusal" || ko "2.1" "stderr=$stderr"
echo "$stderr" | grep -q -- "--ticket=<child-id>" \
  && ok "2.2 stderr hints at child-id command" || ko "2.2" "stderr=$stderr"

# 3. Epic refusal regardless of config flags (cannot be overridden)
out=$(apply_filter "$EPIC" "false" "false" 2>/dev/null); rc=$?
[ "$rc" -eq 20 ] && ok "3.1 epic refused even when checks disabled" || ko "3.1" "rc=$rc"

# 4. Non-epic types do NOT exit 20
US='{"platform_id":"#101","story_type":"user-story"}'
out=$(apply_filter "$US" "true" "true" 2>/dev/null); rc=$?
[ "$rc" -eq 0 ] && ok "4.1 user-story exits 0" || ko "4.1" "rc=$rc"

TASK='{"platform_id":"#102","story_type":"task"}'
out=$(apply_filter "$TASK" "true" "true" 2>/dev/null); rc=$?
[ "$rc" -eq 0 ] && ok "4.2 task exits 0" || ko "4.2" "rc=$rc"

BUG='{"platform_id":"#103","story_type":"bug"}'
out=$(apply_filter "$BUG" "true" "true" 2>/dev/null); rc=$?
[ "$rc" -eq 0 ] && ok "4.3 bug exits 0" || ko "4.3" "rc=$rc"

# 5. Missing story_type defaults to user-story → no refusal
NOTYPE='{"platform_id":"#104"}'
out=$(apply_filter "$NOTYPE" "true" "true" 2>/dev/null); rc=$?
[ "$rc" -eq 0 ] && ok "5.1 missing story_type does not trigger epic refusal" || ko "5.1" "rc=$rc"

echo ""
echo "=== Summary ==="
echo "Passed: ${PASS}"
echo "Failed: ${FAIL}"
[ "$FAIL" -gt 0 ] && { printf '  - %s\n' "${ERRORS[@]}"; exit 1; }
exit 0
