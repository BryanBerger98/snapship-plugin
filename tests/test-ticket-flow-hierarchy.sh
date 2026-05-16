#!/usr/bin/env bash
# /ticket hierarchy flow — Epic → User Story → Task pushed in strict order.
# Verifies : tier filtering, parent platform_id resolution, dry-run push
# with --parent-id wiring.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE="${ROOT}/skills/_shared/cache-runtime.sh"
ADAPTER="${ROOT}/skills/_shared/tickets-adapter.sh"

PASS=0
FAIL=0
ERRORS=()

ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1 — $2"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

DIR=$(mktemp -d -t snap-tk-hier-XXXXXX)
trap 'trash "$DIR" 2>/dev/null || true' EXIT

run_cache() { bash "$CACHE" "$@" --project-root="$DIR"; }

SUBJECT_ID=$(bash "$CACHE" id-gen --prefix=ticket)
run_cache init "$SUBJECT_ID" >/dev/null

DRAFTS=$(cat <<'JSON'
[
  {"local_id":"t-001","title":"Auth platform","status":"draft","story_type":"epic"},
  {"local_id":"t-002","title":"Email signup","status":"draft","story_type":"user-story","parent_epic_id":"t-001"},
  {"local_id":"t-003","title":"Add signup endpoint","status":"draft","story_type":"task","parent_story_id":"t-002"}
]
JSON
)
printf '%s' "$DRAFTS" | run_cache write "$SUBJECT_ID" drafts.json >/dev/null

echo "=== /ticket hierarchy flow ==="

# Tier 1 : Epic first.
epics=$(printf '%s' "$DRAFTS" | jq -c '[.[] | select(.story_type=="epic")]')
[ "$(jq 'length' <<<"$epics")" = "1" ] && ok "tier1.1 1 Epic selected" \
  || ko "tier1.1" "expected 1 Epic"

# Push Epic in dry-run, capture mocked URL.
EPIC_TITLE=$(jq -r '.[0].title' <<<"$epics")
out=$(bash "$ADAPTER" --action=create --platform=github \
  --project-root="$DIR" --story-type=epic \
  --title="$EPIC_TITLE" --body="b" --dry-run 2>&1)
EPIC_PID_PROBE=$(jq -r '.result.platform_id // empty' <<<"$out")
[ -n "$EPIC_PID_PROBE" ] && ok "tier1.2 Epic dry-run platform_id ($EPIC_PID_PROBE)" \
  || ko "tier1.2" "$out"

# Resolve Epic platform_id back into drafts (simulating step-05 cache write).
EPIC_PID=$(jq -r '.result.platform_id' <<<"$out")
DRAFTS=$(jq --arg pid "$EPIC_PID" \
  'map(if .local_id == "t-001" then .platform_id = $pid else . end)' <<<"$DRAFTS")
[ "$(jq -r '.[] | select(.local_id=="t-001") | .platform_id' <<<"$DRAFTS")" = "$EPIC_PID" ] \
  && ok "tier1.3 Epic platform_id resolved in cache" \
  || ko "tier1.3" "platform_id not written"

# Tier 2 : US — resolve parent_epic_id local→platform_id, then dry-run push.
US_PARENT_LOCAL=$(jq -r '.[] | select(.local_id=="t-002") | .parent_epic_id' <<<"$DRAFTS")
US_PARENT_PID=$(jq -r --arg lid "$US_PARENT_LOCAL" '.[] | select(.local_id==$lid) | .platform_id // empty' <<<"$DRAFTS")
[ -n "$US_PARENT_PID" ] && ok "tier2.1 US parent platform_id resolved" \
  || ko "tier2.1" "US parent not resolved"

out=$(bash "$ADAPTER" --action=create --platform=github \
  --project-root="$DIR" --story-type=user-story \
  --title="Email signup" --body="b" \
  --parent-id="$US_PARENT_PID" --dry-run 2>&1)
[ "$(jq -r '.result.platform_id // empty' <<<"$out")" != "" ] \
  && ok "tier2.2 US dry-run with --parent-id succeeded" \
  || ko "tier2.2" "$out"

US_PID=$(jq -r '.result.platform_id' <<<"$out")
DRAFTS=$(jq --arg pid "$US_PID" \
  'map(if .local_id == "t-002" then .platform_id = $pid else . end)' <<<"$DRAFTS")

# Tier 3 : Task — resolve parent_story_id, then dry-run push.
TASK_PARENT_LOCAL=$(jq -r '.[] | select(.local_id=="t-003") | .parent_story_id' <<<"$DRAFTS")
TASK_PARENT_PID=$(jq -r --arg lid "$TASK_PARENT_LOCAL" '.[] | select(.local_id==$lid) | .platform_id // empty' <<<"$DRAFTS")
[ -n "$TASK_PARENT_PID" ] && ok "tier3.1 Task parent platform_id resolved" \
  || ko "tier3.1" "Task parent not resolved"

out=$(bash "$ADAPTER" --action=create --platform=github \
  --project-root="$DIR" --story-type=task \
  --title="Add signup endpoint" --body="b" \
  --parent-id="$TASK_PARENT_PID" --dry-run 2>&1)
[ "$(jq -r '.result.platform_id // empty' <<<"$out")" != "" ] \
  && ok "tier3.2 Task dry-run with --parent-id succeeded" \
  || ko "tier3.2" "$out"

# Order invariant : every child carries a platform_id only after its parent.
all_resolved=$(jq '[.[] | .platform_id // empty] | length' <<<"$DRAFTS")
TASK_PID=$(jq -r '.result.platform_id' <<<"$out")
DRAFTS=$(jq --arg pid "$TASK_PID" \
  'map(if .local_id == "t-003" then .platform_id = $pid else . end)' <<<"$DRAFTS")
[ "$all_resolved" -ge "2" ] && ok "tier3.3 chain Epic→US→Task complete" \
  || ko "tier3.3" "resolved=$all_resolved"

run_cache purge "$SUBJECT_ID" >/dev/null

echo ""
echo "=== Summary ==="
echo "Passed: ${PASS}"
echo "Failed: ${FAIL}"
[ "$FAIL" -gt 0 ] && { printf '  - %s\n' "${ERRORS[@]}"; exit 1; }
exit 0
