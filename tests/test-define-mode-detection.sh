#!/usr/bin/env bash
# /define multimode router — lexicon-driven mode detection.
# Loads skills/define/_keywords.json (single source of truth) and runs a
# corpus of 10 FR + 10 EN prompts per mode (60 cases) plus flag short-circuit
# and ambiguous handling. Passing threshold: ≥ 90 % corpus correctness.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
KEYWORDS_FILE="$ROOT_DIR/skills/define/_keywords.json"

PASS=0
FAIL=0
ERRORS=()

ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1 — $2"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

[ -f "$KEYWORDS_FILE" ] || { echo "FATAL: _keywords.json missing at $KEYWORDS_FILE"; exit 1; }
jq empty "$KEYWORDS_FILE" 2>/dev/null || { echo "FATAL: _keywords.json not valid JSON"; exit 1; }

# Normalize a string : lowercase, strip punctuation (incl. apostrophe), collapse
# whitespace, pad with one leading and one trailing space. Pairing input and
# keyword normalization lets us match by simple substring (case-insensitive,
# word-boundary safe).
normalize_text() {
  local s
  s=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  s=$(printf '%s' "$s" | sed -e 's/[][(){}<>,.;:!?"`/-]/ /g' -e "s/'/ /g")
  s=$(printf '%s' "$s" | sed -e 's/  */ /g')
  printf ' %s ' "$s"
}

# Pre-load normalized keyword lists per mode (FR ∪ EN).
load_keywords_norm() {
  local mode="$1" kw
  while IFS= read -r kw; do
    [ -z "$kw" ] && continue
    normalize_text "$kw"
    printf '\n'
  done < <(jq -r --arg m "$mode" '.categories[$m] | (.fr + .en) | .[]' "$KEYWORDS_FILE")
}

VISION_KW_NORM="$(load_keywords_norm vision)"
JOURNEY_KW_NORM="$(load_keywords_norm journey)"
STORY_KW_NORM="$(load_keywords_norm story)"

count_matches() {
  local padded="$1" kw_norm="$2" count=0 kw
  while IFS= read -r kw; do
    [ -z "$kw" ] && continue
    case "$padded" in
      *"$kw"*) count=$((count + 1)) ;;
    esac
  done <<< "$kw_norm"
  printf '%s' "$count"
}

detect_mode() {
  local mode_flag="$1" raw="$2"
  if [ -n "$mode_flag" ]; then
    case "$mode_flag" in
      vision|journey|story) echo "$mode_flag"; return 0 ;;
      *) return 1 ;;
    esac
  fi
  local padded sv sj ss max mode ties
  padded=$(normalize_text "$raw")
  sv=$(count_matches "$padded" "$VISION_KW_NORM")
  sj=$(count_matches "$padded" "$JOURNEY_KW_NORM")
  ss=$(count_matches "$padded" "$STORY_KW_NORM")
  if [ "$sv" -eq 0 ] && [ "$sj" -eq 0 ] && [ "$ss" -eq 0 ]; then
    echo "ambiguous"
    return 0
  fi
  max="$sv"; mode="vision"
  if [ "$sj" -gt "$max" ]; then max="$sj"; mode="journey"; fi
  if [ "$ss" -gt "$max" ]; then max="$ss"; mode="story"; fi
  ties=0
  [ "$sv" -eq "$max" ] && ties=$((ties + 1))
  [ "$sj" -eq "$max" ] && ties=$((ties + 1))
  [ "$ss" -eq "$max" ] && ties=$((ties + 1))
  if [ "$ties" -gt 1 ]; then
    echo "ambiguous"
    return 0
  fi
  echo "$mode"
}

echo "=== /define mode detection (lexicon-driven) ==="

# 1. --mode= flag short-circuits keyword scan.
[ "$(detect_mode vision  '')" = "vision"  ] && ok "1.1 --mode=vision  short-circuits" || ko "1.1" "missed"
[ "$(detect_mode journey '')" = "journey" ] && ok "1.2 --mode=journey short-circuits" || ko "1.2" "missed"
[ "$(detect_mode story   '')" = "story"   ] && ok "1.3 --mode=story   short-circuits" || ko "1.3" "missed"
detect_mode bogus '' 2>/dev/null && ko "1.4" "wrongly accepted bogus" || ok "1.4 rejects unknown mode"

# 2. Flag wins over conflicting text.
[ "$(detect_mode story 'Définir la vision produit et les principes')" = "story" ] \
  && ok "2.1 flag overrides vision-keyword text" || ko "2.1" "keyword leaked"

# 3. Ambiguous prompt deferred.
[ "$(detect_mode '' 'do something nice please')" = "ambiguous" ] \
  && ok "3.1 ambiguous prompt deferred" || ko "3.1" "auto-picked"

# 4. Empty raw input → ambiguous (defer to user, no silent story fallback).
[ "$(detect_mode '' '')" = "ambiguous" ] \
  && ok "3.2 empty input deferred (no silent fallback)" || ko "3.2" "auto-picked"

# 5. Lexicon-driven corpus (10 FR + 10 EN per mode = 60 cases).
declare -a VISION_FR=(
  "Définir la vision produit et la métrique north star"
  "Quelle est notre mission long terme"
  "Clarifier les principes directeurs du produit"
  "Notre ambition pour les trois prochaines années"
  "Charte produit et raison d être pour orienter l équipe"
  "Définir l étoile polaire et les valeurs"
  "Stratégie produit et positionnement produit"
  "Posons les principes du produit ensemble"
  "Manifeste produit pour orienter l équipe"
  "Cap produit et objectifs produit clairs"
)
declare -a VISION_EN=(
  "Define product vision and north star metric"
  "What is our long term vision"
  "Clarify the guiding principles of the product"
  "Our ambition for the next three years"
  "Set the product charter and purpose"
  "Define product strategy and big picture"
  "Establish guiding values and product positioning"
  "Polestar metric and product objectives"
  "Product manifesto for the team"
  "Product mission and long term vision"
)
declare -a JOURNEY_FR=(
  "Ajouter un parcours utilisateur onboarding"
  "Carte d expérience pour le flow utilisateur inscription"
  "Décrire les étapes utilisateur du checkout"
  "Scénario navigation depuis la home"
  "Walkthrough du tunnel utilisateur"
  "Journey map du parcours d achat"
  "Trajet utilisateur entre login et dashboard"
  "Séquence d écrans onboarding flow"
  "Cheminement complet du parcours"
  "Carte parcours et expérience map"
)
declare -a JOURNEY_EN=(
  "Add the onboarding user journey"
  "Design the user flow for signup"
  "Describe the user steps for checkout"
  "Scenario navigation from the home screen"
  "Walkthrough for the new experience map"
  "Journey map for the purchase path"
  "User path between login and dashboard"
  "Sequence of screens in the onboarding flow"
  "Interaction flow and story arc"
  "Funnel flow for the checkout journey"
)
declare -a STORY_FR=(
  "Nouvelle feature signup avec PRD"
  "Story utilisateur pour la facturation"
  "Spécification de la fonctionnalité paiement"
  "PRD pour la gestion des factures"
  "Critères d acceptation pour le module export"
  "Ticket sur la création de compte"
  "Persona cible et user story checkout"
  "Use case import et exigence métier"
  "Spec de la fonctionnalité notifications"
  "Epic facturation avec scope défini"
)
declare -a STORY_EN=(
  "Build the signup feature PRD"
  "User story for the billing module"
  "Specification for the payment feature"
  "PRD for invoice management"
  "Acceptance criteria for the export module"
  "Ticket on the account creation flow"
  "Persona target and user story checkout"
  "Use case import and business requirement"
  "Spec for notifications feature"
  "Epic billing with defined scope"
)

correct=0
total=0

run_corpus() {
  local expected="$1" label="$2"
  shift 2
  local prompt got
  for prompt in "$@"; do
    total=$((total + 1))
    got=$(detect_mode "" "$prompt")
    if [ "$got" = "$expected" ]; then
      correct=$((correct + 1))
    else
      echo "  miss [$label] got=$got want=$expected — $prompt"
    fi
  done
}

run_corpus vision  "vision FR"  "${VISION_FR[@]}"
run_corpus vision  "vision EN"  "${VISION_EN[@]}"
run_corpus journey "journey FR" "${JOURNEY_FR[@]}"
run_corpus journey "journey EN" "${JOURNEY_EN[@]}"
run_corpus story   "story FR"   "${STORY_FR[@]}"
run_corpus story   "story EN"   "${STORY_EN[@]}"

pct=$(( correct * 100 / total ))
echo ""
echo "=== Corpus: ${correct}/${total} correct (${pct}%) ==="

if [ "$pct" -ge 90 ]; then
  ok "4.1 corpus ≥ 90% (${pct}%)"
else
  ko "4.1" "corpus below 90% (${pct}%)"
fi

echo ""
echo "=== Summary ==="
echo "Passed: ${PASS}"
echo "Failed: ${FAIL}"
[ "$FAIL" -gt 0 ] && { printf '  - %s\n' "${ERRORS[@]}"; exit 1; }
exit 0
