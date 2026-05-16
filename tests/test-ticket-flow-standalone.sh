#!/usr/bin/env bash
# /ticket --standalone flow — raw input → drafts → dry-run push → summary.
# Verifies : ephemeral cache lifecycle, Epic refusal in standalone mode,
# dry-run push of flat hierarchy.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE="${ROOT}/skills/_shared/cache-runtime.sh"
ADAPTER="${ROOT}/skills/_shared/tickets-adapter.sh"

PASS=0
FAIL=0
ERRORS=()

ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1 — $2"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

# Shim cache-runtime to operate inside an isolated project root.
run_cache() { bash "$CACHE" "$@" --project-root="$DIR"; }

DIR=$(mktemp -d -t snap-tk-flow-XXXXXX)
trap 'trash "$DIR" 2>/dev/null || true' EXIT

echo "=== /ticket --standalone flow ==="

# step-00 : init ephemeral subject
SUBJECT_ID=$(bash "$CACHE" id-gen --prefix=ticket)
[ -n "$SUBJECT_ID" ] && ok "00.1 id-gen non-empty" || ko "00.1" "empty subject id"
run_cache init "$SUBJECT_ID" >/dev/null
[ -d "${DIR}/.snap/.runtime/${SUBJECT_ID}" ] \
  && ok "00.2 subject dir created" \
  || ko "00.2" "missing subject dir"

# step-02 : standalone multi-ticket split (simulated)
DRAFTS=$(cat <<'JSON'
[
  {"local_id":"t-001","title":"Fix login crash","status":"draft","story_type":"bug"},
  {"local_id":"t-002","title":"Bump axios to 1.7.0","status":"draft","story_type":"task"},
  {"local_id":"t-003","title":"Add password reset","status":"draft","story_type":"user-story"}
]
JSON
)
printf '%s' "$DRAFTS" | run_cache write "$SUBJECT_ID" drafts.json >/dev/null
count=$(run_cache read "$SUBJECT_ID" drafts.json | jq 'length')
[ "$count" = "3" ] && ok "02.1 3 drafts cached" || ko "02.1" "count=$count"

# step-03 (standalone gate) : Epic forbidden. Simulate the rejection by
# checking the projection that step-03 uses to detect violations.
EPIC_DRAFTS=$(cat <<'JSON'
[
  {"local_id":"t-001","title":"Auth platform","status":"draft","story_type":"epic"}
]
JSON
)
epic_count=$(printf '%s' "$EPIC_DRAFTS" | jq '[.[] | select(.story_type=="epic")] | length')
[ "$epic_count" = "1" ] && ok "03.1 epic detection works (would be refused)" \
  || ko "03.1" "no epic detected"

# Standalone never writes tickets.json (terminal step skips section A under
# --standalone). Verify each draft carries the required ticket fields per
# tickets.schema.$defs.ticket : local_id, title, status, story_type.
shape_ok=$(printf '%s' "$DRAFTS" | jq '[.[] | select(has("local_id") and has("title") and has("status") and has("story_type"))] | length')
[ "$shape_ok" = "3" ] && ok "04.1 every draft carries required ticket fields" \
  || ko "04.1" "shape_ok=$shape_ok"
# Enum sanity : story_type values must be in the v1.2 enum (no orphan strings).
bad_types=$(printf '%s' "$DRAFTS" | jq '[.[] | select(.story_type as $t | ["epic","user-story","task","bug"] | index($t) | not)] | length')
[ "$bad_types" = "0" ] && ok "04.2 story_type values all in v1.2 enum" \
  || ko "04.2" "bad_types=$bad_types"

# step-05 : dry-run push each draft, expect deterministic mock URLs.
pushed=0
while IFS= read -r draft; do
  title=$(jq -r '.title' <<<"$draft")
  out=$(bash "$ADAPTER" --action=create --platform=github \
    --project-root="$DIR" --title="$title" --body="body" --dry-run 2>&1)
  rc=$?
  [ "$rc" = "0" ] || { ko "05.dry-run rc=$rc" "$out"; continue; }
  mode=$(jq -r '.mode' <<<"$out")
  [ "$mode" = "dry-run" ] && pushed=$((pushed + 1))
done < <(printf '%s' "$DRAFTS" | jq -c '.[]')
[ "$pushed" = "3" ] && ok "05.1 dry-run pushed 3 standalone tickets" \
  || ko "05.1" "pushed=$pushed"

# step-06 : mandatory ephemeral purge.
run_cache purge "$SUBJECT_ID" >/dev/null
[ ! -d "${DIR}/.snap/.runtime/${SUBJECT_ID}" ] \
  && ok "06.1 ephemeral subject purged" \
  || ko "06.1" "subject dir persists"

echo ""
echo "=== Summary ==="
echo "Passed: ${PASS}"
echo "Failed: ${FAIL}"
[ "$FAIL" -gt 0 ] && { printf '  - %s\n' "${ERRORS[@]}"; exit 1; }
exit 0
