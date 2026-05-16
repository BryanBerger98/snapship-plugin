#!/usr/bin/env bash
# /define --mode=story — verify the PRD flow's two v1.2 additions:
#  (1) define-state.sh add-feature accepts parent_epic_{id,title,pending}
#  (2) the step-04-render manifest patch produces a valid manifest under
#      the v1.0 manifest schema (parent_epic_title/parent_epic_pending added).
# The full step-03/04 prompt is markdown — this test exercises the helper
# contracts the rendered logic relies on.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFST="${ROOT}/skills/_shared/define-state.sh"
SETUP="${ROOT}/skills/_shared/setup-snap-dir.sh"
SCHEMA="${ROOT}/skills/_shared/schemas/manifest.schema.json"

PASS=0
FAIL=0
ERRORS=()

setup_dir() { mktemp -d -t snap-story-XXXXXX; }
ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1 — $2"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

echo "=== /define --mode=story ==="

# 1. add-feature accepts parent_epic_id (mode "existant")
DIR=$(setup_dir)
bash "$DEFST" init --project-root="$DIR" --lang=en --codebase-mode=greenfield >/dev/null
FT_EXISTING='{
  "story_id":"01-auth",
  "feature_title":"Sign-up with email",
  "feature_status":"refined",
  "priority":"must",
  "problem_statement":"Users cannot create accounts and they are blocked from the product.",
  "solution_overview":"Add email signup flow.",
  "acceptance_criteria":[{"ac_id":"1","ac_text":"User can sign up with email"}],
  "in_scope":"email",
  "out_of_scope":"OAuth",
  "parent_epic_id":"AUTH-1",
  "parent_epic_title":null,
  "parent_epic_pending":false,
  "domains":["auth"],
  "impacted_journeys":[{"domain":"auth","journey_slug":"login-flow"}]
}'
bash "$DEFST" add-feature "$FT_EXISTING" --project-root="$DIR" >/dev/null
F="${DIR}/.snap/.define-state.json"
[ "$(jq -r '.features[0].parent_epic_id' "$F")" = "AUTH-1" ] \
  && ok "1.1 parent_epic_id persisted" || ko "1.1" "diff"
[ "$(jq -r '.features[0].parent_epic_pending' "$F")" = "false" ] \
  && ok "1.2 pending=false (existing mode)" || ko "1.2" "diff"

# 2. add-feature accepts parent_epic_title + pending (mode "à créer")
FT_PENDING='{
  "story_id":"02-signup",
  "feature_title":"Signup hook into onboarding",
  "feature_status":"refined",
  "priority":"must",
  "problem_statement":"Designers want a frictionless signup before onboarding picks up.",
  "solution_overview":"Hook signup into onboarding journey.",
  "acceptance_criteria":[{"ac_id":"1","ac_text":"New user lands on onboarding"}],
  "in_scope":"signup hand-off",
  "out_of_scope":"oauth providers",
  "parent_epic_id":null,
  "parent_epic_title":"Authentication platform",
  "parent_epic_pending":true,
  "domains":["auth"],
  "impacted_journeys":[{"domain":"auth","journey_slug":"signup-flow"}]
}'
bash "$DEFST" add-feature "$FT_PENDING" --project-root="$DIR" >/dev/null
[ "$(jq -r '.features[1].parent_epic_title' "$F")" = "Authentication platform" ] \
  && ok "2.1 parent_epic_title persisted" || ko "2.1" "diff"
[ "$(jq -r '.features[1].parent_epic_pending' "$F")" = "true" ] \
  && ok "2.2 pending=true (to-create mode)" || ko "2.2" "diff"

# 3. add-feature without parent_epic_* — feature autonomous
FT_NONE='{
  "story_id":"03-billing",
  "feature_title":"Plan upgrade",
  "feature_status":"refined",
  "priority":"should",
  "problem_statement":"Power users hit free-tier limits weekly and cannot upgrade.",
  "solution_overview":"Add upgrade modal.",
  "acceptance_criteria":[{"ac_id":"1","ac_text":"User can upgrade plan"}],
  "in_scope":"upgrade modal",
  "out_of_scope":"downgrade",
  "domains":["billing"],
  "impacted_journeys":[]
}'
bash "$DEFST" add-feature "$FT_NONE" --project-root="$DIR" >/dev/null
pe=$(jq -r '.features[2].parent_epic_id // "null"' "$F")
pt=$(jq -r '.features[2].parent_epic_title // "null"' "$F")
[ "$pe" = "null" ] && [ "$pt" = "null" ] \
  && ok "3.1 autonomous feature has no parent_epic_*" || ko "3.1" "leaked pe=$pe pt=$pt"

# 4. Manifest patch (mode "existant") — mirror step-04-render.md section C
bash "$SETUP" --project-root="$DIR" --story-id=01-auth --story-name="Sign-up with email" >/dev/null
MANIFEST="${DIR}/.snap/manifests/01-auth.manifest.json"
fid="01-auth"
DOMAINS_JSON=$(jq -c --arg fid "$fid" \
  '.features[] | select(.story_id == $fid) | .domains' "$F")
JOURNEYS_JSON=$(jq -c --arg fid "$fid" \
  '.features[] | select(.story_id == $fid)
   | .impacted_journeys | map({domain: .domain, journey_slug: .journey_slug})' "$F")
PRIORITY=$(jq -r --arg fid "$fid" \
  '.features[] | select(.story_id == $fid) | .priority' "$F")
PARENT_EPIC_ID=$(jq -r --arg fid "$fid" \
  '.features[] | select(.story_id == $fid) | .parent_epic_id // ""' "$F")
PARENT_EPIC_TITLE=$(jq -r --arg fid "$fid" \
  '.features[] | select(.story_id == $fid) | .parent_epic_title // ""' "$F")
PARENT_EPIC_PENDING=$(jq -r --arg fid "$fid" \
  '.features[] | select(.story_id == $fid) | .parent_epic_pending // false' "$F")
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

tmp=$(mktemp)
jq --arg prio "$PRIORITY" \
   --argjson domains "$DOMAINS_JSON" \
   --argjson journeys "$JOURNEYS_JSON" \
   --arg pepic "$PARENT_EPIC_ID" \
   --arg petitle "$PARENT_EPIC_TITLE" \
   --argjson ppending "$PARENT_EPIC_PENDING" \
   --arg ts "$NOW" '
  .priority = $prio
  | .domains = $domains
  | .impacted_journeys = $journeys
  | (if $pepic   != "" then .parent_epic_id    = $pepic   else . end)
  | (if $petitle != "" then .parent_epic_title = $petitle else . end)
  | (if $ppending == true then .parent_epic_pending = true else . end)
  | .updated_at = $ts
' "$MANIFEST" > "$tmp" && mv "$tmp" "$MANIFEST"

[ "$(jq -r '.parent_epic_id' "$MANIFEST")" = "AUTH-1" ] \
  && ok "4.1 manifest.parent_epic_id from add-feature" || ko "4.1" "diff"
[ "$(jq -r '.parent_epic_pending // "absent"' "$MANIFEST")" = "absent" ] \
  && ok "4.2 manifest does not set pending=false unnecessarily" \
  || ko "4.2" "leaked pending key"

# 5. Manifest patch (mode "à créer") — pending=true + parent_epic_title set
bash "$SETUP" --project-root="$DIR" --story-id=02-signup --story-name="Signup hook" >/dev/null
M2="${DIR}/.snap/manifests/02-signup.manifest.json"
fid="02-signup"
DOMAINS_JSON=$(jq -c --arg fid "$fid" \
  '.features[] | select(.story_id == $fid) | .domains' "$F")
JOURNEYS_JSON=$(jq -c --arg fid "$fid" \
  '.features[] | select(.story_id == $fid)
   | .impacted_journeys | map({domain: .domain, journey_slug: .journey_slug})' "$F")
PRIORITY=$(jq -r --arg fid "$fid" \
  '.features[] | select(.story_id == $fid) | .priority' "$F")
PARENT_EPIC_ID=$(jq -r --arg fid "$fid" \
  '.features[] | select(.story_id == $fid) | .parent_epic_id // ""' "$F")
PARENT_EPIC_TITLE=$(jq -r --arg fid "$fid" \
  '.features[] | select(.story_id == $fid) | .parent_epic_title // ""' "$F")
PARENT_EPIC_PENDING=$(jq -r --arg fid "$fid" \
  '.features[] | select(.story_id == $fid) | .parent_epic_pending // false' "$F")

tmp=$(mktemp)
jq --arg prio "$PRIORITY" \
   --argjson domains "$DOMAINS_JSON" \
   --argjson journeys "$JOURNEYS_JSON" \
   --arg pepic "$PARENT_EPIC_ID" \
   --arg petitle "$PARENT_EPIC_TITLE" \
   --argjson ppending "$PARENT_EPIC_PENDING" \
   --arg ts "$NOW" '
  .priority = $prio
  | .domains = $domains
  | .impacted_journeys = $journeys
  | (if $pepic   != "" then .parent_epic_id    = $pepic   else . end)
  | (if $petitle != "" then .parent_epic_title = $petitle else . end)
  | (if $ppending == true then .parent_epic_pending = true else . end)
  | .updated_at = $ts
' "$M2" > "$tmp" && mv "$tmp" "$M2"

[ "$(jq -r '.parent_epic_title' "$M2")" = "Authentication platform" ] \
  && ok "5.1 manifest.parent_epic_title from to-create mode" || ko "5.1" "diff"
[ "$(jq -r '.parent_epic_pending' "$M2")" = "true" ] \
  && ok "5.2 manifest.parent_epic_pending=true" || ko "5.2" "diff"
[ "$(jq -r '.parent_epic_id // "absent"' "$M2")" = "absent" ] \
  && ok "5.3 no spurious parent_epic_id for to-create mode" || ko "5.3" "leaked"

# 6. Schema validates both manifests
if command -v ajv >/dev/null 2>&1; then
  if ajv validate -s "$SCHEMA" -d "$MANIFEST" --spec=draft2020 --strict=false >/dev/null 2>&1; then
    ok "6.1 ajv validates existing-Epic manifest"
  else
    ko "6.1" "ajv rejected MANIFEST"
  fi
  if ajv validate -s "$SCHEMA" -d "$M2" --spec=draft2020 --strict=false >/dev/null 2>&1; then
    ok "6.2 ajv validates pending-Epic manifest"
  else
    ko "6.2" "ajv rejected M2"
  fi
else
  ok "6.1 ajv not installed, skipping"
  ok "6.2 ajv not installed, skipping"
fi

# 7. validate (define-state) accepts the assembled state.
# Seed the rest of the state (vision, north star, persona) so validate runs on
# the full shape — the assertion is "parent_epic_* fields do not break validate".
bash "$DEFST" set vision \
  "A platform that helps freelance designers organize and ship client work end-to-end so they can deliver more value faster." \
  --project-root="$DIR" >/dev/null
bash "$DEFST" set north_star_metric  "WAU"     --project-root="$DIR" >/dev/null
bash "$DEFST" set north_star_current "1200"    --project-root="$DIR" >/dev/null
bash "$DEFST" set north_star_target  "5000"    --project-root="$DIR" >/dev/null
bash "$DEFST" set target_horizon     "Q3 2026" --project-root="$DIR" >/dev/null
PERSONA='{"persona_name":"Sarah","persona_role":"freelance designer","persona_goals":"ship work","persona_pains":"context switching","persona_tools":"Figma"}'
bash "$DEFST" add-persona "$PERSONA" --project-root="$DIR" >/dev/null
# Feature 03-billing currently has impacted_journeys=[] but feature_status="refined"
# — validate per the v0.2 contract requires ≥1 in_scope/out_of_scope/AC, which is met.
if bash "$DEFST" validate --project-root="$DIR" >/dev/null 2>&1; then
  ok "7.1 define-state validate OK with parent_epic_* mix"
else
  ko "7.1" "validate rejected full state with parent_epic_* mix"
fi

trash "$DIR" 2>/dev/null || true

echo ""
echo "=== Summary ==="
echo "Passed: ${PASS}"
echo "Failed: ${FAIL}"
[ "$FAIL" -gt 0 ] && { printf '  - %s\n' "${ERRORS[@]}"; exit 1; }
exit 0
