#!/usr/bin/env bash
# Tests for skills/_shared/define-state.sh

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/skills/_shared/define-state.sh"

PASS=0
FAIL=0
ERRORS=()

setup_dir() { mktemp -d -t snap-defst-XXXXXX; }
ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

VALID_VISION="A platform that helps freelance designers organize and ship client work without context switching, so they can deliver more in less time."

echo "=== define-state.sh tests ==="

# 1. init creates valid file
echo ""
echo "[1] init"
DIR=$(setup_dir)
bash "$SCRIPT" init --project-root="$DIR" --lang=en --codebase-mode=greenfield --define-mode=story
F="${DIR}/.snap/.define-state.json"
[ -f "$F" ] && ok "1.1 file created" || ko "1.1 missing"
jq empty "$F" 2>/dev/null && ok "1.2 valid JSON" || ko "1.2 invalid JSON"
[ "$(jq -r '.lang' "$F")" = "en" ] && ok "1.3 lang stored" || ko "1.3"
[ "$(jq -r '.codebase_mode' "$F")" = "greenfield" ] && ok "1.4 codebase_mode stored" || ko "1.4"
[ "$(jq -r '.define_mode' "$F")" = "story" ] && ok "1.5 define_mode stored" || ko "1.5"

# 1bis. init merge — second call only updates passed flags
DIR2=$(setup_dir)
bash "$SCRIPT" init --project-root="$DIR2" --lang=fr --define-mode=vision
bash "$SCRIPT" init --project-root="$DIR2" --codebase-mode=extension
F2="${DIR2}/.snap/.define-state.json"
[ "$(jq -r '.lang' "$F2")" = "fr" ] && ok "1.6 merge preserves lang" || ko "1.6"
[ "$(jq -r '.define_mode' "$F2")" = "vision" ] && ok "1.7 merge preserves define_mode" || ko "1.7"
[ "$(jq -r '.codebase_mode' "$F2")" = "extension" ] && ok "1.8 merge sets codebase_mode" || ko "1.8"
trash "$DIR2" 2>/dev/null || true

# 1ter. init rejects deprecated --mode= flag
DIR3=$(setup_dir)
if bash "$SCRIPT" init --project-root="$DIR3" --mode=greenfield 2>/dev/null; then
  ko "1.9 --mode= should be rejected"
else
  ok "1.9 --mode= rejected (deprecated)"
fi
trash "$DIR3" 2>/dev/null || true

# 1ter-b. --story= sets active_story_id (N5/N6)
DIR_S=$(setup_dir)
bash "$SCRIPT" init --project-root="$DIR_S" --define-mode=story --story=01-auth
F_S="${DIR_S}/.snap/.define-state.json"
[ "$(jq -r '.active_story_id' "$F_S")" = "01-auth" ] && ok "1.9b --story= sets active_story_id" || ko "1.9b"
trash "$DIR_S" 2>/dev/null || true

# 1ter-c. --story-id= synonym
DIR_SI=$(setup_dir)
bash "$SCRIPT" init --project-root="$DIR_SI" --define-mode=story --story-id=03-payments
F_SI="${DIR_SI}/.snap/.define-state.json"
[ "$(jq -r '.active_story_id' "$F_SI")" = "03-payments" ] && ok "1.9c --story-id= synonym" || ko "1.9c"
trash "$DIR_SI" 2>/dev/null || true

# 1ter-d. --feature= deprecated alias still works + emits warning
DIR_F=$(setup_dir)
warn=$(bash "$SCRIPT" init --project-root="$DIR_F" --define-mode=story --feature=02-billing 2>&1 >/dev/null)
F_F="${DIR_F}/.snap/.define-state.json"
[ "$(jq -r '.active_story_id' "$F_F")" = "02-billing" ] && ok "1.9d --feature= alias still maps to active_story_id" || ko "1.9d"
echo "$warn" | grep -q "deprecated" && ok "1.9e --feature= emits deprecation warning" || ko "1.9e got: $warn"
trash "$DIR_F" 2>/dev/null || true

# 1quater. cli_parent_epic_id is a settable scalar (N4)
DIR4=$(setup_dir)
bash "$SCRIPT" init --project-root="$DIR4"
F4="${DIR4}/.snap/.define-state.json"
[ "$(jq -r '.cli_parent_epic_id' "$F4")" = "" ] && ok "1.10 cli_parent_epic_id default empty" || ko "1.10"
bash "$SCRIPT" set cli_parent_epic_id "AUTH-1" --project-root="$DIR4"
got=$(bash "$SCRIPT" get cli_parent_epic_id --project-root="$DIR4")
[ "$got" = "AUTH-1" ] && ok "1.11 cli_parent_epic_id round-trip" || ko "1.11 got $got"
trash "$DIR4" 2>/dev/null || true

trash "$DIR" 2>/dev/null || true

# 1quinquies. config_snapshot round-trip (T3 / Phase 19)
DIR_CS=$(setup_dir)
bash "$SCRIPT" init --project-root="$DIR_CS"
F_CS="${DIR_CS}/.snap/.define-state.json"
[ "$(jq -c '.config_snapshot' "$F_CS")" = "{}" ] && ok "1.12 config_snapshot defaults to {}" || ko "1.12"
SNAP='{"documentation":{"platform":"affine","paths":{"prd_root":"PRDs","functional_root":"Functional"}}}'
bash "$SCRIPT" set-config-snapshot "$SNAP" --project-root="$DIR_CS"
got=$(bash "$SCRIPT" get-config-snapshot --project-root="$DIR_CS")
[ "$(echo "$got" | jq -r '.documentation.platform')" = "affine" ] && ok "1.13 set/get-config-snapshot round-trip" || ko "1.13 got $got"
# Reject non-object payload
if bash "$SCRIPT" set-config-snapshot '"scalar"' --project-root="$DIR_CS" 2>/dev/null; then
  ko "1.14 should reject scalar payload"
else
  ok "1.14 set-config-snapshot rejects non-object"
fi
trash "$DIR_CS" 2>/dev/null || true

# 2. set/get scalar
echo ""
echo "[2] set/get"
DIR=$(setup_dir)
bash "$SCRIPT" init --project-root="$DIR"
bash "$SCRIPT" set vision "$VALID_VISION" --project-root="$DIR"
got=$(bash "$SCRIPT" get vision --project-root="$DIR")
[ "$got" = "$VALID_VISION" ] && ok "2.1 round-trip vision" || ko "2.1"
trash "$DIR" 2>/dev/null || true

# 3. set rejects unknown key
echo ""
echo "[3] set bad key"
DIR=$(setup_dir)
bash "$SCRIPT" init --project-root="$DIR"
if bash "$SCRIPT" set bogus_key "x" --project-root="$DIR" 2>/dev/null; then
  ko "3.1 should have rejected"
else
  ok "3.1 rejected unknown key"
fi
trash "$DIR" 2>/dev/null || true

# 4. add-persona appends
echo ""
echo "[4] add-persona"
DIR=$(setup_dir)
bash "$SCRIPT" init --project-root="$DIR"
P='{"persona_name":"Sarah","persona_role":"freelance designer","persona_goals":"ship work","persona_pains":"context switching","persona_tools":"Figma"}'
bash "$SCRIPT" add-persona "$P" --project-root="$DIR"
F="${DIR}/.snap/.define-state.json"
n=$(jq '.personas | length' "$F")
[ "$n" = "1" ] && ok "4.1 persona appended" || ko "4.1 n=$n"
[ "$(jq -r '.personas[0].persona_name' "$F")" = "Sarah" ] && ok "4.2 name preserved" || ko "4.2"
trash "$DIR" 2>/dev/null || true

# 5. add-feature appends
echo ""
echo "[5] add-feature"
DIR=$(setup_dir)
bash "$SCRIPT" init --project-root="$DIR"
FT='{"story_id":"01-auth","feature_title":"Sign-up","feature_status":"refined","priority":"must","problem_statement":"Users cannot create accounts and they are blocked from using the product.","solution_overview":"Add email signup.","acceptance_criteria":[{"ac_id":"1","ac_text":"User can sign up with email"}],"in_scope":"email","out_of_scope":"OAuth"}'
bash "$SCRIPT" add-feature "$FT" --project-root="$DIR"
F="${DIR}/.snap/.define-state.json"
n=$(jq '.features | length' "$F")
[ "$n" = "1" ] && ok "5.1 feature appended" || ko "5.1 n=$n"
trash "$DIR" 2>/dev/null || true

# 6. list-personas / list-features (NDJSON)
echo ""
echo "[6] list (NDJSON)"
DIR=$(setup_dir)
bash "$SCRIPT" init --project-root="$DIR"
bash "$SCRIPT" add-persona '{"persona_name":"A","persona_role":"r","persona_goals":"g","persona_pains":"p"}' --project-root="$DIR"
bash "$SCRIPT" add-persona '{"persona_name":"B","persona_role":"r","persona_goals":"g","persona_pains":"p"}' --project-root="$DIR"
n=$(bash "$SCRIPT" list-personas --project-root="$DIR" | wc -l | tr -d ' ')
[ "$n" = "2" ] && ok "6.1 list-personas count" || ko "6.1 n=$n"
trash "$DIR" 2>/dev/null || true

# 7. validate — fresh state fails (empty)
echo ""
echo "[7] validate — empty state"
DIR=$(setup_dir)
bash "$SCRIPT" init --project-root="$DIR"
if bash "$SCRIPT" validate --project-root="$DIR" 2>/dev/null; then
  ko "7.1 should have failed"
else
  ok "7.1 empty state rejected"
fi
trash "$DIR" 2>/dev/null || true

# 8. validate — happy path
echo ""
echo "[8] validate — happy path"
DIR=$(setup_dir)
bash "$SCRIPT" init --project-root="$DIR"
bash "$SCRIPT" set vision "$VALID_VISION"          --project-root="$DIR"
bash "$SCRIPT" set north_star_metric "WAU"         --project-root="$DIR"
bash "$SCRIPT" set north_star_current "0"          --project-root="$DIR"
bash "$SCRIPT" set north_star_target "1000"        --project-root="$DIR"
bash "$SCRIPT" set target_horizon "Q4 2026"        --project-root="$DIR"
bash "$SCRIPT" add-persona '{"persona_name":"A","persona_role":"r","persona_goals":"g","persona_pains":"p"}' --project-root="$DIR"
bash "$SCRIPT" add-feature '{"story_id":"01-x","feature_title":"X","feature_status":"refined","priority":"must","problem_statement":"This is a real problem statement that is long enough.","solution_overview":"Do X.","acceptance_criteria":[{"ac_id":"1","ac_text":"AC1"}],"in_scope":"a","out_of_scope":"b"}' --project-root="$DIR"
if bash "$SCRIPT" validate --project-root="$DIR" 2>/dev/null; then
  ok "8.1 validate happy path"
else
  ko "8.1 should have passed"
fi
trash "$DIR" 2>/dev/null || true

# 9. validate — vision too short
echo ""
echo "[9] validate — vision too short"
DIR=$(setup_dir)
bash "$SCRIPT" init --project-root="$DIR"
bash "$SCRIPT" set vision "short" --project-root="$DIR"
if bash "$SCRIPT" validate --project-root="$DIR" 2>/dev/null; then
  ko "9.1 should have failed"
else
  ok "9.1 short vision rejected"
fi
trash "$DIR" 2>/dev/null || true

# 10. validate — duplicate story_id
echo ""
echo "[10] validate — duplicate story_id"
DIR=$(setup_dir)
bash "$SCRIPT" init --project-root="$DIR"
bash "$SCRIPT" set vision "$VALID_VISION"   --project-root="$DIR"
bash "$SCRIPT" set north_star_metric "WAU"  --project-root="$DIR"
bash "$SCRIPT" set north_star_current "0"   --project-root="$DIR"
bash "$SCRIPT" set north_star_target "1000" --project-root="$DIR"
bash "$SCRIPT" set target_horizon "Q4 2026" --project-root="$DIR"
bash "$SCRIPT" add-persona '{"persona_name":"A","persona_role":"r","persona_goals":"g","persona_pains":"p"}' --project-root="$DIR"
bash "$SCRIPT" add-feature '{"story_id":"01-x","feature_title":"X","feature_status":"draft","priority":"must"}' --project-root="$DIR"
bash "$SCRIPT" add-feature '{"story_id":"01-x","feature_title":"Y","feature_status":"draft","priority":"should"}' --project-root="$DIR"
out=$(bash "$SCRIPT" validate --project-root="$DIR" 2>&1)
echo "$out" | grep -q "duplicate" && ok "10.1 duplicate detected" || ko "10.1: $out"
trash "$DIR" 2>/dev/null || true

# 11. validate — no must priority
echo ""
echo "[11] validate — no must"
DIR=$(setup_dir)
bash "$SCRIPT" init --project-root="$DIR"
bash "$SCRIPT" set vision "$VALID_VISION"   --project-root="$DIR"
bash "$SCRIPT" set north_star_metric "WAU"  --project-root="$DIR"
bash "$SCRIPT" set north_star_current "0"   --project-root="$DIR"
bash "$SCRIPT" set north_star_target "1000" --project-root="$DIR"
bash "$SCRIPT" set target_horizon "Q4 2026" --project-root="$DIR"
bash "$SCRIPT" add-persona '{"persona_name":"A","persona_role":"r","persona_goals":"g","persona_pains":"p"}' --project-root="$DIR"
bash "$SCRIPT" add-feature '{"story_id":"01-x","feature_title":"X","feature_status":"draft","priority":"should"}' --project-root="$DIR"
out=$(bash "$SCRIPT" validate --project-root="$DIR" 2>&1)
echo "$out" | grep -q "no must-priority" && ok "11.1 no-must detected" || ko "11.1: $out"
trash "$DIR" 2>/dev/null || true

# 12. wipe
echo ""
echo "[12] wipe"
DIR=$(setup_dir)
bash "$SCRIPT" init --project-root="$DIR"
F="${DIR}/.snap/.define-state.json"
[ -f "$F" ] && ok "12.1 created" || ko "12.1"
bash "$SCRIPT" wipe --project-root="$DIR"
[ ! -f "$F" ] && ok "12.2 wiped" || ko "12.2"
trash "$DIR" 2>/dev/null || true

# 13. path
echo ""
echo "[13] path"
DIR=$(setup_dir)
out=$(bash "$SCRIPT" path --project-root="$DIR")
[ "$out" = "${DIR}/.snap/.define-state.json" ] && ok "13.1 path printed" || ko "13.1 got $out"
trash "$DIR" 2>/dev/null || true

# 14. usage
echo ""
echo "[14] usage"
bash "$SCRIPT" >/dev/null 2>&1
[ $? -eq 2 ] && ok "14.1 no args = exit 2" || ko "14.1"
bash "$SCRIPT" --help >/dev/null
[ $? -eq 0 ] && ok "14.2 --help = exit 0" || ko "14.2"
bash "$SCRIPT" bogus >/dev/null 2>&1
[ $? -eq 2 ] && ok "14.3 unknown cmd = exit 2" || ko "14.3"

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
