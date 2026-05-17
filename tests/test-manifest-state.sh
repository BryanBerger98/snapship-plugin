#!/usr/bin/env bash
# Tests for skills/_shared/manifest-state.sh — patch feature manifest from
# define-state (T2 / Phase 18).

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/skills/_shared/manifest-state.sh"

PASS=0
FAIL=0
ERRORS=()

ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1 — $2"; FAIL=$((FAIL + 1)); ERRORS+=("$1: $2"); }

setup_dir() { mktemp -d -t snap-manifest-XXXXXX; }

# Scaffold a minimal valid define-state + manifest pair.
# Args: DIR STORY_ID [PRIORITY] [PARENT_EPIC_ID] [PARENT_EPIC_TITLE] [PARENT_EPIC_PENDING]
scaffold() {
  local dir="$1" fid="$2"
  local prio="${3:-must}"
  local pepic="${4:-}"
  local petitle="${5:-}"
  local ppending="${6:-false}"
  mkdir -p "${dir}/.snap/manifests"
  # Build feature object piece by piece to handle empty optionals.
  local feature
  feature=$(jq -n \
    --arg fid "$fid" \
    --arg prio "$prio" \
    --arg pepic "$pepic" \
    --arg petitle "$petitle" \
    --argjson ppending "$ppending" \
    '{
       story_id: $fid,
       story_name: "Test Feature",
       priority: $prio,
       domains: ["auth", "billing"],
       impacted_journeys: [
         {domain: "auth", journey_slug: "signup"},
         {domain: "billing", journey_slug: "checkout"}
       ]
     }
     | (if $pepic != "" then .parent_epic_id = $pepic else . end)
     | (if $petitle != "" then .parent_epic_title = $petitle else . end)
     | (if $ppending == true then .parent_epic_pending = true else . end)')
  jq -n --argjson f "$feature" '{ features: [ $f ] }' > "${dir}/.snap/.define-state.json"
  # Manifest skeleton (mimics setup-snap-dir.sh output, minus updated_at).
  jq -n --arg fid "$fid" '{
    schema_version: "1.0.0",
    story_id: $fid,
    story_name: "Test Feature",
    state: "defined",
    created_at: "2026-01-01T00:00:00Z",
    refs: {}
  }' > "${dir}/.snap/manifests/${fid}.manifest.json"
}

echo "=== manifest-state.sh — patch-from-define-state ==="

echo ""
echo "[1] standard patch — priority, domains, journeys, updated_at"

DIR=$(setup_dir)
scaffold "$DIR" "01-auth"
if bash "$SCRIPT" patch-from-define-state --project-root="$DIR" --story-id=01-auth >/dev/null 2>&1; then
  F="${DIR}/.snap/manifests/01-auth.manifest.json"
  prio=$(jq -r '.priority' "$F")
  domains=$(jq -c '.domains' "$F")
  jcount=$(jq '.impacted_journeys | length' "$F")
  ts=$(jq -r '.updated_at' "$F")
  [ "$prio" = "must" ] && \
    [ "$domains" = '["auth","billing"]' ] && \
    [ "$jcount" = "2" ] && \
    [[ "$ts" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]] && \
    ok "1.1 priority+domains+journeys+updated_at applied" || \
    ko "1.1" "prio=$prio domains=$domains jcount=$jcount ts=$ts"
else
  ko "1.1" "helper rc != 0"
fi
trash "$DIR" 2>/dev/null || true

echo ""
echo "[2] parent_epic_id present → field set"

DIR=$(setup_dir)
scaffold "$DIR" "02-billing" must "EPIC-42"
bash "$SCRIPT" patch-from-define-state --project-root="$DIR" --story-id=02-billing >/dev/null 2>&1
got=$(jq -r '.parent_epic_id' "${DIR}/.snap/manifests/02-billing.manifest.json")
[ "$got" = "EPIC-42" ] && ok "2.1 parent_epic_id set" || ko "2.1" "got=$got"
trash "$DIR" 2>/dev/null || true

echo ""
echo "[3] parent_epic_pending=true → field set"

DIR=$(setup_dir)
scaffold "$DIR" "03-inbox" should "" "Onboarding Epic" true
bash "$SCRIPT" patch-from-define-state --project-root="$DIR" --story-id=03-inbox >/dev/null 2>&1
F="${DIR}/.snap/manifests/03-inbox.manifest.json"
ppending=$(jq -r '.parent_epic_pending' "$F")
petitle=$(jq -r '.parent_epic_title' "$F")
[ "$ppending" = "true" ] && [ "$petitle" = "Onboarding Epic" ] && \
  ok "3.1 parent_epic_pending + title set" || \
  ko "3.1" "ppending=$ppending petitle=$petitle"
trash "$DIR" 2>/dev/null || true

echo ""
echo "[4] parent_epic_title empty → field absent"

DIR=$(setup_dir)
scaffold "$DIR" "04-search" could
bash "$SCRIPT" patch-from-define-state --project-root="$DIR" --story-id=04-search >/dev/null 2>&1
F="${DIR}/.snap/manifests/04-search.manifest.json"
has_title=$(jq 'has("parent_epic_title")' "$F")
has_id=$(jq 'has("parent_epic_id")' "$F")
has_pending=$(jq 'has("parent_epic_pending")' "$F")
[ "$has_title" = "false" ] && [ "$has_id" = "false" ] && [ "$has_pending" = "false" ] && \
  ok "4.1 empty optional epic fields not written" || \
  ko "4.1" "title=$has_title id=$has_id pending=$has_pending"
trash "$DIR" 2>/dev/null || true

echo ""
echo "[5] manifest absent → rc=1"

DIR=$(setup_dir)
mkdir -p "${DIR}/.snap/manifests"
jq -n '{features: [{story_id: "05-ghost", story_name: "Ghost", priority: "must", domains: [], impacted_journeys: []}]}' \
  > "${DIR}/.snap/.define-state.json"
err=$(bash "$SCRIPT" patch-from-define-state --project-root="$DIR" --story-id=05-ghost 2>&1); rc=$?
[ "$rc" = "1" ] && echo "$err" | grep -q "manifest not found" && \
  ok "5.1 missing manifest → rc=1 with clear error" || \
  ko "5.1" "rc=$rc err=$err"
trash "$DIR" 2>/dev/null || true

echo ""
echo "[6] story_id absent from state → rc=1"

DIR=$(setup_dir)
scaffold "$DIR" "06-real"
# Manifest exists for 99-bogus but features[] has no matching story_id —
# isolates the "story_id not in state" error from "manifest missing".
jq -n '{
  schema_version: "1.0.0",
  story_id: "99-bogus",
  story_name: "Bogus",
  state: "defined",
  created_at: "2026-01-01T00:00:00Z",
  refs: {}
}' > "${DIR}/.snap/manifests/99-bogus.manifest.json"
err=$(bash "$SCRIPT" patch-from-define-state --project-root="$DIR" --story-id=99-bogus 2>&1); rc=$?
[ "$rc" = "1" ] && echo "$err" | grep -q "not found in" && \
  ok "6.1 unknown story_id → rc=1 with clear error" || \
  ko "6.1" "rc=$rc err=$err"
trash "$DIR" 2>/dev/null || true

echo ""
echo "[7] usage errors → rc=2"

# 7.1 no subcommand
err=$(bash "$SCRIPT" 2>&1); rc=$?
[ "$rc" = "2" ] && ok "7.1 no args → rc=2" || ko "7.1" "rc=$rc"

# 7.2 unknown subcommand
err=$(bash "$SCRIPT" bogus 2>&1); rc=$?
[ "$rc" = "2" ] && ok "7.2 unknown subcommand → rc=2" || ko "7.2" "rc=$rc"

# 7.3 missing required flag
err=$(bash "$SCRIPT" patch-from-define-state --project-root=/tmp 2>&1); rc=$?
[ "$rc" = "2" ] && ok "7.3 missing --story-id → rc=2" || ko "7.3" "rc=$rc"

# 7.4 unknown flag
err=$(bash "$SCRIPT" patch-from-define-state --project-root=/tmp --story-id=01-x --foo=bar 2>&1); rc=$?
[ "$rc" = "2" ] && ok "7.4 unknown flag → rc=2" || ko "7.4" "rc=$rc"

# 7.5 define-state missing
DIR=$(setup_dir)
mkdir -p "${DIR}/.snap/manifests"
err=$(bash "$SCRIPT" patch-from-define-state --project-root="$DIR" --story-id=01-x 2>&1); rc=$?
[ "$rc" = "1" ] && echo "$err" | grep -q "define-state not found" && \
  ok "7.5 missing define-state → rc=1" || \
  ko "7.5" "rc=$rc err=$err"
trash "$DIR" 2>/dev/null || true

echo ""
echo "[8] idempotent — re-run same inputs preserves payload (modulo updated_at)"

DIR=$(setup_dir)
scaffold "$DIR" "08-idem" should "EPIC-1"
bash "$SCRIPT" patch-from-define-state --project-root="$DIR" --story-id=08-idem >/dev/null 2>&1
F="${DIR}/.snap/manifests/08-idem.manifest.json"
hash1=$(jq -S 'del(.updated_at)' "$F" | shasum | awk '{print $1}')
sleep 1
bash "$SCRIPT" patch-from-define-state --project-root="$DIR" --story-id=08-idem >/dev/null 2>&1
hash2=$(jq -S 'del(.updated_at)' "$F" | shasum | awk '{print $1}')
[ "$hash1" = "$hash2" ] && ok "8.1 payload stable across re-runs" || ko "8.1" "h1=$hash1 h2=$hash2"
# updated_at must have advanced.
t1_t2_check=$(jq -r '.updated_at' "$F")
[ -n "$t1_t2_check" ] && ok "8.2 updated_at refreshed" || ko "8.2" "empty"
trash "$DIR" 2>/dev/null || true

echo ""
echo "=== Summary ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "Errors:"
  for e in "${ERRORS[@]}"; do
    echo "  - $e"
  done
  exit 1
fi
