#!/usr/bin/env bash
# Tests for skills/_shared/worktree-helper.sh
# Usage: bash tests/test-worktree-helper.sh

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/skills/_shared/worktree-helper.sh"

PASS=0
FAIL=0
ERRORS=()

ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

CFG='{"defaults":{"worktree":{"path":"./.worktrees","destroy":"after_merge"}}}'

echo "=== worktree-helper.sh tests ==="

# 1. user-story → dedicated worktree
echo ""
echo "[1] user-story dedicated"
T='{"story_type":"user-story","branch_name":"feat/repo-101-pdf"}'
out=$(bash "$SCRIPT" resolve --ticket-json="$T" --config-json="$CFG")
[ "$(echo "$out" | jq -r '.strategy')" = "dedicated" ] && ok "1.1 strategy dedicated" || ko "1.1 got: $out"
[ "$(echo "$out" | jq -r '.branch_name')" = "feat/repo-101-pdf" ] && ok "1.2 branch" || ko "1.2"
[ "$(echo "$out" | jq -r '.worktree_path')" = "./.worktrees/feat/repo-101-pdf" ] && ok "1.3 path" || ko "1.3"

# 2. bug → dedicated
echo ""
echo "[2] bug dedicated"
T='{"story_type":"bug","branch_name":"fix/repo-150-pdf"}'
out=$(bash "$SCRIPT" resolve --ticket-json="$T" --config-json="$CFG")
[ "$(echo "$out" | jq -r '.strategy')" = "dedicated" ] && ok "2.1 bug dedicated" || ko "2.1"
[ "$(echo "$out" | jq -r '.branch_name')" = "fix/repo-150-pdf" ] && ok "2.2 branch" || ko "2.2"

# 3. epic → error (no branch ever)
echo ""
echo "[3] epic refused"
T='{"story_type":"epic"}'
if bash "$SCRIPT" resolve --ticket-json="$T" --config-json="$CFG" 2>/dev/null; then
  ko "3.1 should refuse epic"
else
  ok "3.1 epic refused"
fi

# 4. task child of user-story → reuse parent worktree
echo ""
echo "[4] task child of user-story reuses parent"
T='{"story_type":"task","parent_story_id":"#101","branch_name":"feat/repo-102-task"}'
P='{"story_type":"user-story","branch_name":"feat/repo-101-pdf"}'
out=$(bash "$SCRIPT" resolve --ticket-json="$T" --parent-json="$P" --config-json="$CFG")
[ "$(echo "$out" | jq -r '.strategy')" = "reuse" ] && ok "4.1 reuse strategy" || ko "4.1 got: $out"
[ "$(echo "$out" | jq -r '.branch_name')" = "feat/repo-101-pdf" ] && ok "4.2 parent branch" || ko "4.2"
[ "$(echo "$out" | jq -r '.worktree_path')" = "./.worktrees/feat/repo-101-pdf" ] && ok "4.3 parent path" || ko "4.3"

# 5. task child of bug → dedicated (own branch)
echo ""
echo "[5] task child of bug dedicated"
T='{"story_type":"task","parent_story_id":"#301","branch_name":"fix/repo-302-test"}'
P='{"story_type":"bug","branch_name":"fix/repo-301-login"}'
out=$(bash "$SCRIPT" resolve --ticket-json="$T" --parent-json="$P" --config-json="$CFG")
[ "$(echo "$out" | jq -r '.strategy')" = "dedicated" ] && ok "5.1 dedicated" || ko "5.1 got: $out"
[ "$(echo "$out" | jq -r '.branch_name')" = "fix/repo-302-test" ] && ok "5.2 own branch" || ko "5.2"

# 6. task child of epic (parent_epic_id only) → dedicated
echo ""
echo "[6] task child of epic dedicated"
T='{"story_type":"task","parent_epic_id":"#42","branch_name":"feat/repo-200-task"}'
out=$(bash "$SCRIPT" resolve --ticket-json="$T" --config-json="$CFG")
[ "$(echo "$out" | jq -r '.strategy')" = "dedicated" ] && ok "6.1 dedicated" || ko "6.1 got: $out"

# 7. task standalone → dedicated
echo ""
echo "[7] task standalone"
T='{"story_type":"task","branch_name":"build/repo-200-node-22"}'
out=$(bash "$SCRIPT" resolve --ticket-json="$T" --config-json="$CFG")
[ "$(echo "$out" | jq -r '.strategy')" = "dedicated" ] && ok "7.1 dedicated" || ko "7.1 got: $out"

# 8. task with parent_story_id but missing --parent-json → error
echo ""
echo "[8] task with parent_story_id requires --parent-json"
T='{"story_type":"task","parent_story_id":"#101","branch_name":"feat/x"}'
if bash "$SCRIPT" resolve --ticket-json="$T" --config-json="$CFG" 2>/dev/null; then
  ko "8.1 should require parent-json"
else
  ok "8.1 refuses without parent-json"
fi

# 9. missing branch_name (US) → error
echo ""
echo "[9] user-story missing branch_name"
T='{"story_type":"user-story"}'
if bash "$SCRIPT" resolve --ticket-json="$T" --config-json="$CFG" 2>/dev/null; then
  ko "9.1 should require branch_name"
else
  ok "9.1 refuses missing branch_name"
fi

# 10. missing story_type → error
echo ""
echo "[10] missing story_type"
T='{"branch_name":"feat/x"}'
if bash "$SCRIPT" resolve --ticket-json="$T" --config-json="$CFG" 2>/dev/null; then
  ko "10.1 should require story_type"
else
  ok "10.1 refuses missing story_type"
fi

# 11. unknown story_type → error
echo ""
echo "[11] unknown story_type"
T='{"story_type":"spike","branch_name":"x"}'
if bash "$SCRIPT" resolve --ticket-json="$T" --config-json="$CFG" 2>/dev/null; then
  ko "11.1 should refuse unknown"
else
  ok "11.1 refuses unknown story_type"
fi

# 12. config path picked up from custom config
echo ""
echo "[12] custom config path"
CUSTOM_CFG='{"defaults":{"worktree":{"path":"/srv/wt","destroy":"after_merge"}}}'
T='{"story_type":"user-story","branch_name":"b1"}'
out=$(bash "$SCRIPT" resolve --ticket-json="$T" --config-json="$CUSTOM_CFG")
[ "$(echo "$out" | jq -r '.worktree_path')" = "/srv/wt/b1" ] && ok "12.1 custom path used" || ko "12.1 got: $out"

# 13. path subcommand
echo ""
echo "[13] path subcommand"
out=$(bash "$SCRIPT" path "feat/x" --config-json="$CFG")
[ "$out" = "./.worktrees/feat/x" ] && ok "13.1" || ko "13.1 got: $out"

# 14. destroy-decision matrix
echo ""
echo "[14] destroy-decision"
# after_merge → only merge phase destroys
bash "$SCRIPT" destroy-decision --phase=develop --config-destroy=after_merge 2>/dev/null && ko "14.1 develop@after_merge should NOT destroy" || ok "14.1 develop@after_merge keeps"
bash "$SCRIPT" destroy-decision --phase=review --config-destroy=after_merge 2>/dev/null && ko "14.2 review@after_merge keeps" || ok "14.2 review@after_merge keeps"
bash "$SCRIPT" destroy-decision --phase=merge --config-destroy=after_merge && ok "14.3 merge@after_merge destroys" || ko "14.3"

# after_develop → all phases ≥ develop destroy
bash "$SCRIPT" destroy-decision --phase=develop --config-destroy=after_develop && ok "14.4 develop@after_develop destroys" || ko "14.4"
bash "$SCRIPT" destroy-decision --phase=review --config-destroy=after_develop && ok "14.5 review@after_develop destroys" || ko "14.5"
bash "$SCRIPT" destroy-decision --phase=merge --config-destroy=after_develop && ok "14.6 merge@after_develop destroys" || ko "14.6"

# after_review → review + merge destroy, develop keeps
bash "$SCRIPT" destroy-decision --phase=develop --config-destroy=after_review 2>/dev/null && ko "14.7 develop@after_review keeps" || ok "14.7"
bash "$SCRIPT" destroy-decision --phase=review --config-destroy=after_review && ok "14.8 review@after_review destroys" || ko "14.8"

# 15. invalid args
echo ""
echo "[15] invalid args"
bash "$SCRIPT" destroy-decision --phase=bogus --config-destroy=after_merge 2>/dev/null && ko "15.1 should reject bogus phase" || ok "15.1"
bash "$SCRIPT" destroy-decision --phase=develop --config-destroy=never 2>/dev/null && ko "15.2 should reject bad destroy" || ok "15.2"
bash "$SCRIPT" 2>/dev/null; [ $? -eq 1 ] && ok "15.3 no args = 1" || ko "15.3"
bash "$SCRIPT" --help >/dev/null && ok "15.4 --help = 0" || ko "15.4"

echo ""
echo "=== Summary ==="
echo "Passed: ${PASS}"
echo "Failed: ${FAIL}"

if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "Errors:"
  printf '  - %s\n' "${ERRORS[@]}"
  exit 1
fi
