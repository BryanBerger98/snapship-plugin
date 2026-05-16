#!/usr/bin/env bash
# /ticket blocked-child flow — parent Epic create fails, child US transitions
# to status=blocked with explicit UX message. Verifies the blocage rule from
# step-05 (decision 7b).

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE="${ROOT}/skills/_shared/cache-runtime.sh"

PASS=0
FAIL=0
ERRORS=()

ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1 — $2"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

DIR=$(mktemp -d -t snap-tk-blk-XXXXXX)
trap 'trash "$DIR" 2>/dev/null || true' EXIT

run_cache() { bash "$CACHE" "$@" --project-root="$DIR"; }

SUBJECT_ID=$(bash "$CACHE" id-gen --prefix=ticket)
run_cache init "$SUBJECT_ID" >/dev/null

# Initial drafts : Epic + US referencing it + standalone Task (control).
DRAFTS=$(cat <<'JSON'
[
  {"local_id":"t-001","title":"Auth platform","status":"draft","story_type":"epic"},
  {"local_id":"t-002","title":"Email signup","status":"draft","story_type":"user-story","parent_epic_id":"t-001"},
  {"local_id":"t-003","title":"Add signup endpoint","status":"draft","story_type":"task","parent_story_id":"t-002"},
  {"local_id":"t-004","title":"Bump axios","status":"draft","story_type":"task"}
]
JSON
)
printf '%s' "$DRAFTS" | run_cache write "$SUBJECT_ID" drafts.json >/dev/null

echo "=== /ticket blocked-child flow ==="

# Simulate Tier 1 Epic push FAILURE — platform_id stays unset on t-001.
# (No mutation needed — drafts already have no platform_id.)

# Apply step-05 blocage rule : every child of an unpushed parent → status=blocked.
# Tier 2 first (US referencing Epic parent), then Tier 3 (Task referencing US
# parent — which may itself have just been blocked).
block_unpushed_parents() {
  local input="$1"
  printf '%s' "$input" | jq '
    . as $all
    | map(
        . as $self
        | (
            ($self.parent_epic_id // null) // null
          ) as $pe
        | (
            ($self.parent_story_id // null) // null
          ) as $ps
        | ($all | map(select(.local_id == $pe))[0]) as $parent_epic
        | ($all | map(select(.local_id == $ps))[0]) as $parent_story
        | if ($pe != null) and (($parent_epic.platform_id // "") == "") then
            $self + {status:"blocked", blocked_reason:("parent " + $pe + " non poussé")}
          elif ($ps != null) and (($parent_story.platform_id // "") == "" or ($parent_story.status // "") == "blocked") then
            $self + {status:"blocked", blocked_reason:("parent " + $ps + " non poussé")}
          else $self end
      )
  '
}

# Run twice to propagate transitively (Task→US blocked→Task blocked).
DRAFTS=$(block_unpushed_parents "$DRAFTS")
DRAFTS=$(block_unpushed_parents "$DRAFTS")

# Assert US blocked.
us_status=$(jq -r '.[] | select(.local_id=="t-002") | .status' <<<"$DRAFTS")
[ "$us_status" = "blocked" ] && ok "blk.1 US blocked when Epic parent unpushed" \
  || ko "blk.1" "us_status=$us_status"

# Assert blocked_reason carries explicit parent ref.
us_reason=$(jq -r '.[] | select(.local_id=="t-002") | .blocked_reason' <<<"$DRAFTS")
[[ "$us_reason" == *"t-001"* ]] && ok "blk.2 UX message references parent local_id" \
  || ko "blk.2" "us_reason=$us_reason"

# Assert Task blocked transitively (parent US is also blocked).
task_status=$(jq -r '.[] | select(.local_id=="t-003") | .status' <<<"$DRAFTS")
[ "$task_status" = "blocked" ] && ok "blk.3 Task transitively blocked (parent US blocked)" \
  || ko "blk.3" "task_status=$task_status"

# Assert standalone Task (t-004) NOT blocked — no parent dep.
standalone_status=$(jq -r '.[] | select(.local_id=="t-004") | .status' <<<"$DRAFTS")
[ "$standalone_status" = "draft" ] && ok "blk.4 standalone Task unaffected" \
  || ko "blk.4" "standalone_status=$standalone_status"

# Assert Epic itself is NOT blocked (it failed, but it has no parent).
epic_status=$(jq -r '.[] | select(.local_id=="t-001") | .status' <<<"$DRAFTS")
[ "$epic_status" = "draft" ] && ok "blk.5 Epic itself not marked blocked" \
  || ko "blk.5" "epic_status=$epic_status"

# Persist mutated drafts and re-read to confirm cache write round-trips.
echo "$DRAFTS" | run_cache write "$SUBJECT_ID" drafts.json >/dev/null
roundtrip=$(run_cache read "$SUBJECT_ID" drafts.json | jq -r '.[] | select(.local_id=="t-002") | .status')
[ "$roundtrip" = "blocked" ] && ok "blk.6 blocked state persists in cache" \
  || ko "blk.6" "roundtrip=$roundtrip"

run_cache purge "$SUBJECT_ID" >/dev/null

echo ""
echo "=== Summary ==="
echo "Passed: ${PASS}"
echo "Failed: ${FAIL}"
[ "$FAIL" -gt 0 ] && { printf '  - %s\n' "${ERRORS[@]}"; exit 1; }
exit 0
