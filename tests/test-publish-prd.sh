#!/usr/bin/env bash
# Tests for skills/_shared/publish-prd.sh — shell-pure helpers backing
# step-05 publish (T1 / Phase 17).

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/skills/_shared/publish-prd.sh"

PASS=0
FAIL=0
ERRORS=()

ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1 — $2"; FAIL=$((FAIL + 1)); ERRORS+=("$1: $2"); }

setup_dir() { mktemp -d -t snap-publish-XXXXXX; }

# Build a minimal valid define-state + manifest pair.
# Args: DIR FID [SYNC_STATUS]
scaffold() {
  local dir="$1" fid="$2"
  local sync_status="${3:-}"
  mkdir -p "${dir}/.snap/manifests" "${dir}/.snap/PRDs"

  jq -n --arg fid "$fid" '{
    features: [{
      story_id: $fid,
      story_name: "Auth flow rewrite",
      priority: "must",
      domains: ["auth", "billing"],
      impacted_journeys: [
        {domain: "auth",    journey_slug: "signup",   domain_title: "Authentication", journey_title: "Signup"},
        {domain: "billing", journey_slug: "checkout", domain_title: "Billing",        journey_title: "Checkout"}
      ]
    }]
  }' > "${dir}/.snap/.define-state.json"

  jq -n --arg fid "$fid" --arg ss "$sync_status" '
    {
      schema_version: "1.0.0",
      story_id: $fid,
      story_name: "Auth flow rewrite",
      priority: "must",
      state: "defined",
      created_at: "2026-01-01T00:00:00Z",
      domains: ["auth", "billing"],
      impacted_journeys: [
        {domain: "auth", journey_slug: "signup"},
        {domain: "billing", journey_slug: "checkout"}
      ],
      refs: (if $ss != "" then { prd: { sync_status: $ss } } else {} end)
    }
  ' > "${dir}/.snap/manifests/${fid}.manifest.json"
}

echo "=== publish-prd.sh — prepare ==="

echo ""
echo "[1] standard prepare — skip=false, brief well-formed"

DIR=$(setup_dir)
scaffold "$DIR" "01-auth"
BRIEF=$(bash "$SCRIPT" prepare --project-root="$DIR" \
  --manifest="${DIR}/.snap/manifests/01-auth.manifest.json" 2>/dev/null); rc=$?
if [ "$rc" = "0" ] && echo "$BRIEF" | jq empty 2>/dev/null; then
  fid=$(echo "$BRIEF" | jq -r '.fid')
  skip=$(echo "$BRIEF" | jq -r '.skip')
  story_name=$(echo "$BRIEF" | jq -r '.story_name')
  dom_count=$(echo "$BRIEF" | jq '.domains | length')
  jrn_count=$(echo "$BRIEF" | jq '.impacted_journeys | length')
  dt_count=$(echo "$BRIEF"  | jq '.domain_titles | length')
  jt_count=$(echo "$BRIEF"  | jq '.journey_titles | length')
  [ "$fid" = "01-auth" ] && [ "$skip" = "false" ] && [ "$story_name" = "Auth flow rewrite" ] && \
    [ "$dom_count" = "2" ] && [ "$jrn_count" = "2" ] && \
    [ "$dt_count" = "2" ] && [ "$jt_count" = "2" ] && \
    ok "1.1 brief fid+skip+story_name+counts" || \
    ko "1.1" "fid=$fid skip=$skip story=$story_name dom=$dom_count jrn=$jrn_count dt=$dt_count jt=$jt_count"
else
  ko "1.1" "rc=$rc brief=$BRIEF"
fi
trash "$DIR" 2>/dev/null || true

echo ""
echo "[2] skip when refs.prd.sync_status=synced"

DIR=$(setup_dir)
scaffold "$DIR" "02-billing" "synced"
BRIEF=$(bash "$SCRIPT" prepare --project-root="$DIR" \
  --manifest="${DIR}/.snap/manifests/02-billing.manifest.json" 2>/dev/null)
skip=$(echo "$BRIEF" | jq -r '.skip')
reason=$(echo "$BRIEF" | jq -r '.skip_reason')
[ "$skip" = "true" ] && echo "$reason" | grep -q "synced" && \
  ok "2.1 skip=true + reason mentions synced" || \
  ko "2.1" "skip=$skip reason=$reason"
trash "$DIR" 2>/dev/null || true

echo ""
echo "[3] year + month_year match UTC now"

DIR=$(setup_dir)
scaffold "$DIR" "03-now"
BRIEF=$(bash "$SCRIPT" prepare --project-root="$DIR" \
  --manifest="${DIR}/.snap/manifests/03-now.manifest.json" 2>/dev/null)
year=$(echo "$BRIEF" | jq -r '.year')
month_year=$(echo "$BRIEF" | jq -r '.month_year')
expected_year=$(date -u +%Y)
expected_my=$(date -u +%m-%Y)
[ "$year" = "$expected_year" ] && [ "$month_year" = "$expected_my" ] && \
  ok "3.1 year + month_year correct" || \
  ko "3.1" "year=$year month_year=$month_year (expected $expected_year / $expected_my)"
trash "$DIR" 2>/dev/null || true

echo ""
echo "[4] domain_titles + journey_titles resolve from define-state"

DIR=$(setup_dir)
scaffold "$DIR" "04-titles"
BRIEF=$(bash "$SCRIPT" prepare --project-root="$DIR" \
  --manifest="${DIR}/.snap/manifests/04-titles.manifest.json" 2>/dev/null)
dt_auth=$(echo "$BRIEF" | jq -r '.domain_titles[] | select(.domain == "auth") | .title')
jt_signup=$(echo "$BRIEF" | jq -r '.journey_titles[] | select(.journey_slug == "signup") | .title')
[ "$dt_auth" = "Authentication" ] && [ "$jt_signup" = "Signup" ] && \
  ok "4.1 titles resolved from define-state" || \
  ko "4.1" "dt_auth=$dt_auth jt_signup=$jt_signup"
trash "$DIR" 2>/dev/null || true

echo ""
echo "[5] manifest missing → rc=1"

DIR=$(setup_dir)
mkdir -p "${DIR}/.snap/manifests"
jq -n '{features: []}' > "${DIR}/.snap/.define-state.json"
err=$(bash "$SCRIPT" prepare --project-root="$DIR" \
  --manifest="${DIR}/.snap/manifests/ghost.manifest.json" 2>&1); rc=$?
[ "$rc" = "1" ] && echo "$err" | grep -q "manifest not found" && \
  ok "5.1 missing manifest → rc=1" || \
  ko "5.1" "rc=$rc err=$err"
trash "$DIR" 2>/dev/null || true

echo ""
echo "[6] define-state missing → rc=1"

DIR=$(setup_dir)
mkdir -p "${DIR}/.snap/manifests"
jq -n '{
  schema_version: "1.0.0",
  story_id: "06-state",
  story_name: "X",
  state: "defined",
  created_at: "2026-01-01T00:00:00Z",
  refs: {}
}' > "${DIR}/.snap/manifests/06-state.manifest.json"
err=$(bash "$SCRIPT" prepare --project-root="$DIR" \
  --manifest="${DIR}/.snap/manifests/06-state.manifest.json" 2>&1); rc=$?
[ "$rc" = "1" ] && echo "$err" | grep -q "define-state not found" && \
  ok "6.1 missing define-state → rc=1" || \
  ko "6.1" "rc=$rc err=$err"
trash "$DIR" 2>/dev/null || true

echo ""
echo "[7] usage errors → rc=2"

err=$(bash "$SCRIPT" 2>&1); rc=$?
[ "$rc" = "2" ] && ok "7.1 no args → rc=2" || ko "7.1" "rc=$rc"

err=$(bash "$SCRIPT" bogus 2>&1); rc=$?
[ "$rc" = "2" ] && ok "7.2 unknown subcommand → rc=2" || ko "7.2" "rc=$rc"

err=$(bash "$SCRIPT" prepare --project-root=/tmp 2>&1); rc=$?
[ "$rc" = "2" ] && ok "7.3 prepare missing --manifest → rc=2" || ko "7.3" "rc=$rc"

err=$(bash "$SCRIPT" prepare --project-root=/tmp --manifest=/tmp/x --foo=bar 2>&1); rc=$?
[ "$rc" = "2" ] && ok "7.4 prepare unknown flag → rc=2" || ko "7.4" "rc=$rc"

echo ""
echo "=== publish-prd.sh — build-agent-prompt ==="

echo ""
echo "[8] build-agent-prompt — happy path"

DIR=$(setup_dir)
scaffold "$DIR" "08-prompt"
BRIEF=$(bash "$SCRIPT" prepare --project-root="$DIR" \
  --manifest="${DIR}/.snap/manifests/08-prompt.manifest.json" 2>/dev/null)
PROMPT=$(bash "$SCRIPT" build-agent-prompt \
  --brief="$BRIEF" --platform=affine --workspace-id=WS1 \
  --functional-root="Product/Functional" --prd-root="Product/PRDs" \
  --project-root="$DIR" 2>/dev/null); rc=$?
if [ "$rc" = "0" ] && echo "$PROMPT" | grep -q "snap-publisher" \
   && echo "$PROMPT" | grep -q "platform: affine" \
   && echo "$PROMPT" | grep -q "workspace_id: WS1" \
   && echo "$PROMPT" | grep -q "functional_root: Product/Functional" \
   && echo "$PROMPT" | grep -q "prd_root: Product/PRDs" \
   && echo "$PROMPT" | grep -q "08-prompt"; then
  ok "8.1 prompt contains all key fields"
else
  ko "8.1" "rc=$rc prompt missing field"
fi
trash "$DIR" 2>/dev/null || true

echo ""
echo "[9] build-agent-prompt — bad brief → rc=2"

err=$(bash "$SCRIPT" build-agent-prompt \
  --brief='not json' --platform=affine --workspace-id=WS \
  --functional-root=F --prd-root=P --project-root=/tmp 2>&1); rc=$?
[ "$rc" = "2" ] && echo "$err" | grep -q "must be valid JSON" && \
  ok "9.1 invalid brief → rc=2" || \
  ko "9.1" "rc=$rc err=$err"

err=$(bash "$SCRIPT" build-agent-prompt --brief='{}' --platform=affine 2>&1); rc=$?
[ "$rc" = "2" ] && ok "9.2 missing required flags → rc=2" || ko "9.2" "rc=$rc"

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
