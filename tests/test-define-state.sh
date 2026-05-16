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
bash "$SCRIPT" init --project-root="$DIR" --lang=en --mode=greenfield
F="${DIR}/.snap/.define-state.json"
[ -f "$F" ] && ok "1.1 file created" || ko "1.1 missing"
jq empty "$F" 2>/dev/null && ok "1.2 valid JSON" || ko "1.2 invalid JSON"
[ "$(jq -r '.lang' "$F")" = "en" ] && ok "1.3 lang stored" || ko "1.3"
[ "$(jq -r '.mode' "$F")" = "greenfield" ] && ok "1.4 mode stored" || ko "1.4"
trash "$DIR" 2>/dev/null || true

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
