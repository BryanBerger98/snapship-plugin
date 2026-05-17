#!/usr/bin/env bash
# Tests for /snap:define router fast-path — short-circuit when `--mode=`
# is explicit and `--resume` is absent (T7 / Phase 22).
#
# The router itself is LLM-driven, so we cannot test "did the LLM skip
# Phase B/C?" directly. We do test the *mechanism* the fast path relies
# on : `define-state.sh init --define-mode=…` must produce a complete,
# minimal state in a single call, with no side effects on keys that
# weren't passed. This guards against regressions in the merge logic
# that would force step-00-detect-mode to re-invoke `init` (and thus
# spawn duplicate progress entries).

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/skills/_shared/define-state.sh"

PASS=0
FAIL=0
ERRORS=()

setup_dir() { mktemp -d -t snap-fastpath-XXXXXX; }
ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1 — $2"; FAIL=$((FAIL + 1)); ERRORS+=("$1: $2"); }

echo "=== define-mode fast-path contract ==="

echo ""
echo "[1] fast-path init — --define-mode= alone produces complete state"

for mode in vision journey story; do
  DIR=$(setup_dir)
  bash "$SCRIPT" init --project-root="$DIR" --define-mode="$mode"
  F="${DIR}/.snap/.define-state.json"
  if [ ! -f "$F" ]; then
    ko "1.$mode state file" "missing"
    continue
  fi
  if ! jq empty "$F" 2>/dev/null; then
    ko "1.$mode valid JSON" "invalid"
    continue
  fi
  got=$(jq -r '.define_mode' "$F")
  if [ "$got" = "$mode" ]; then
    ok "1.$mode define_mode=$mode persisted"
  else
    ko "1.$mode define_mode" "expected $mode got $got"
  fi
  # Other scalar keys should be present + empty (skeleton fully formed).
  for k in lang codebase_mode active_story_id cli_parent_epic_id vision; do
    val=$(jq -r --arg k "$k" '.[$k]' "$F")
    if [ "$val" != "" ] && [ "$val" != "null" ]; then
      ko "1.$mode.$k empty" "got '$val'"
    fi
  done
  # Arrays default empty.
  pers=$(jq '.personas | length' "$F")
  feat=$(jq '.features | length' "$F")
  [ "$pers" = "0" ] && [ "$feat" = "0" ] && \
    ok "1.$mode arrays default []" || \
    ko "1.$mode arrays" "personas=$pers features=$feat"
  trash "$DIR" 2>/dev/null || true
done

echo ""
echo "[2] idempotent — repeated init with same --define-mode is a no-op"

DIR=$(setup_dir)
bash "$SCRIPT" init --project-root="$DIR" --define-mode=story
F="${DIR}/.snap/.define-state.json"
first_hash=$(jq -S 'del(.created_at)' "$F" | shasum | awk '{print $1}')
bash "$SCRIPT" init --project-root="$DIR" --define-mode=story
second_hash=$(jq -S 'del(.created_at)' "$F" | shasum | awk '{print $1}')
[ "$first_hash" = "$second_hash" ] && \
  ok "2.1 repeated init preserves state (ignoring created_at)" || \
  ko "2.1" "state mutated unexpectedly"
trash "$DIR" 2>/dev/null || true

echo ""
echo "[3] fast-path then story-init — define_mode survives codebase_mode merge"

DIR=$(setup_dir)
# Router fast path : sets only define_mode.
bash "$SCRIPT" init --project-root="$DIR" --define-mode=story
# Story-init step adds codebase_mode + lang later.
bash "$SCRIPT" init --project-root="$DIR" --codebase-mode=greenfield --lang=en
F="${DIR}/.snap/.define-state.json"
dm=$(jq -r '.define_mode' "$F")
cm=$(jq -r '.codebase_mode' "$F")
lg=$(jq -r '.lang' "$F")
[ "$dm" = "story" ] && [ "$cm" = "greenfield" ] && [ "$lg" = "en" ] && \
  ok "3.1 define_mode persists across subsequent merge calls" || \
  ko "3.1" "dm=$dm cm=$cm lg=$lg"
trash "$DIR" 2>/dev/null || true

echo ""
echo "[4] router never falls back to set — single write point"

# The fast-path contract says step-00-detect-mode invokes `init`
# exactly once (no follow-up `set define_mode`). Grep enforces this
# at the source level — if a future edit adds a `set define_mode`
# call to the router, this fails fast.
ROUTER="${ROOT}/skills/define/step-00-detect-mode.md"
if grep -E "define-state\.sh\s+set\s+define_mode" "$ROUTER" >/dev/null 2>&1; then
  ko "4.1" "router contains a 'set define_mode' call — must use init only"
else
  ok "4.1 router has no 'set define_mode' (single write point)"
fi
# Sanity : the router must call init at least once.
grep -E "define-state\.sh.*init" "$ROUTER" >/dev/null 2>&1 && \
  ok "4.2 router calls init (mechanism present)" || \
  ko "4.2" "router missing init call"

echo ""
echo "[5] invalid --define-mode= still produces a state — caller's job to validate"

# define-state.sh init is permissive (it stores whatever string is passed).
# The router (step-00-detect-mode) is responsible for rejecting invalid
# mode values before calling init. Document the contract via test.
DIR=$(setup_dir)
bash "$SCRIPT" init --project-root="$DIR" --define-mode=bogus 2>/dev/null
F="${DIR}/.snap/.define-state.json"
got=$(jq -r '.define_mode' "$F")
[ "$got" = "bogus" ] && \
  ok "5.1 init does not validate mode (router enforces upstream)" || \
  ko "5.1" "got '$got'"
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
