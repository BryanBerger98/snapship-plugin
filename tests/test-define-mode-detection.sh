#!/usr/bin/env bash
# /define multimode router — keyword-based mode detection.
# Mirrors the FR/EN keyword table in skills/define/step-00-detect-mode.md
# and the --mode= flag short-circuit.
#
# This test does NOT run the LLM concertation (impossible offline). It exercises
# the deterministic layer : --mode= flag wins, then keyword fallback.

set -uo pipefail

PASS=0
FAIL=0
ERRORS=()

ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1 — $2"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

# Mirror of the router contract in step-00-detect-mode.md.
detect_mode() {
  local mode_flag="$1" raw="$2"
  if [ -n "$mode_flag" ]; then
    case "$mode_flag" in
      vision|journey|story) echo "$mode_flag"; return 0 ;;
      *) return 1 ;;
    esac
  fi
  local lc
  lc=$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')
  # vision keywords (FR + EN)
  if echo "$lc" | grep -qE '\b(vision|mission|principes|principles|métrique|metric|north[ -]?star|ambition)\b'; then
    echo "vision"; return 0
  fi
  # journey keywords (FR + EN)
  if echo "$lc" | grep -qE '\b(parcours|journey|flow|étapes utilisateur|user steps|scénario|scenario)\b'; then
    echo "journey"; return 0
  fi
  # story keywords (FR + EN)
  if echo "$lc" | grep -qE '\b(feature|story|prd|fonctionnalité|ticket)\b'; then
    echo "story"; return 0
  fi
  # default → ambiguous, caller must ask user
  echo "ambiguous"
}

echo "=== /define mode detection ==="

# 1. --mode flag wins, no LLM call needed.
[ "$(detect_mode vision  '')" = "vision"  ] && ok "1.1 --mode=vision  short-circuits" || ko "1.1" "missed"
[ "$(detect_mode journey '')" = "journey" ] && ok "1.2 --mode=journey short-circuits" || ko "1.2" "missed"
[ "$(detect_mode story   '')" = "story"   ] && ok "1.3 --mode=story   short-circuits" || ko "1.3" "missed"
detect_mode bogus '' 2>/dev/null && ko "1.4" "wrongly accepted bogus" || ok "1.4 rejects unknown mode"

# 2. Keyword detection — FR.
[ "$(detect_mode '' 'Définir la vision produit et la métrique north star')" = "vision" ] \
  && ok "2.1 FR vision keyword" || ko "2.1" "missed"
[ "$(detect_mode '' 'Ajouter un parcours utilisateur onboarding')" = "journey" ] \
  && ok "2.2 FR journey keyword" || ko "2.2" "missed"
[ "$(detect_mode '' 'Nouvelle feature signup avec PRD')" = "story" ] \
  && ok "2.3 FR story keyword" || ko "2.3" "missed"

# 3. Keyword detection — EN.
[ "$(detect_mode '' 'Define the product vision and north-star metric')" = "vision" ] \
  && ok "3.1 EN vision keyword" || ko "3.1" "missed"
[ "$(detect_mode '' 'Add the onboarding user journey')" = "journey" ] \
  && ok "3.2 EN journey keyword" || ko "3.2" "missed"
[ "$(detect_mode '' 'Build the signup feature PRD')" = "story" ] \
  && ok "3.3 EN story keyword" || ko "3.3" "missed"

# 4. Ambiguous prompt → router must defer to user (no auto-pick).
[ "$(detect_mode '' 'do something nice please')" = "ambiguous" ] \
  && ok "4.1 ambiguous prompt deferred" || ko "4.1" "auto-picked"

# 5. Flag takes precedence over conflicting keywords.
[ "$(detect_mode story 'Definir la vision produit')" = "story" ] \
  && ok "5.1 flag overrides vision-keyword text" || ko "5.1" "keyword leaked"

echo ""
echo "=== Summary ==="
echo "Passed: ${PASS}"
echo "Failed: ${FAIL}"
[ "$FAIL" -gt 0 ] && { printf '  - %s\n' "${ERRORS[@]}"; exit 1; }
exit 0
