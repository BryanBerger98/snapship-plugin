#!/usr/bin/env bash
# /define --mode=journey — end-to-end shape of step-00-journey-edit operations
# against taxonomy-state.sh. Covers create / refactor-update / split flows
# via the helper subcommands (draft-journey, set-journey-content).

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAX="${ROOT}/skills/_shared/taxonomy-state.sh"
SCHEMA="${ROOT}/skills/_shared/schemas/taxonomy.schema.json"

PASS=0
FAIL=0
ERRORS=()

setup_dir() { mktemp -d -t snap-journey-XXXXXX; }
ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1 — $2"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

echo "=== /define --mode=journey ==="

# 1. Submode create — journey under existing domain
DIR=$(setup_dir)
bash "$TAX" init --project-root="$DIR" >/dev/null
bash "$TAX" add-domain "auth" "Authentication" "page-d-auth" --project-root="$DIR" >/dev/null
bash "$TAX" draft-journey "auth" "login-flow" "Login Flow" --project-root="$DIR" >/dev/null
F="${DIR}/.snap/manifests/_taxonomy.json"
state=$(jq -r '.domains.auth.journeys["login-flow"].state' "$F")
[ "$state" = "draft" ] && ok "1.1 created journey state=draft" || ko "1.1" "state=$state"
title=$(jq -r '.domains.auth.journeys["login-flow"].title' "$F")
[ "$title" = "Login Flow" ] && ok "1.2 title preserved" || ko "1.2" "diff"
pid=$(jq -r '.domains.auth.journeys["login-flow"].page_id // "null"' "$F")
[ "$pid" = "null" ] && ok "1.3 draft has no page_id" || ko "1.3" "leaked $pid"

# 2. Submode create — top-level journey (domain="_")
bash "$TAX" draft-journey "_" "global-onboarding" "Global Onboarding" --project-root="$DIR" >/dev/null
state=$(jq -r '.journeys["global-onboarding"].state' "$F")
[ "$state" = "draft" ] && ok "2.1 top-journey draft created" || ko "2.1" "state=$state"

# 3. set-journey-content writes steps[] and outcomes[]
STEPS='[{"title":"Land on /login","description":"User opens the login page"},{"title":"Enter credentials"},{"title":"Submit form"}]'
OUTCOMES='["User reaches /dashboard","Session cookie set"]'
bash "$TAX" set-journey-content "auth" "login-flow" "$STEPS" "$OUTCOMES" \
  --project-root="$DIR" >/dev/null
ns=$(jq '.domains.auth.journeys["login-flow"].steps | length' "$F")
[ "$ns" = "3" ] && ok "3.1 steps count" || ko "3.1" "ns=$ns"
no=$(jq '.domains.auth.journeys["login-flow"].outcomes | length' "$F")
[ "$no" = "2" ] && ok "3.2 outcomes count" || ko "3.2" "no=$no"
# Step description survives optional handling
d=$(jq -r '.domains.auth.journeys["login-flow"].steps[0].description' "$F")
[ "$d" = "User opens the login page" ] && ok "3.3 step description preserved" || ko "3.3" "diff"

# 4. Submode refactor — overwrite steps/outcomes on existing journey
STEPS2='[{"title":"Land"},{"title":"Auth"},{"title":"Land on /home"}]'
OUTCOMES2='["User on /home"]'
bash "$TAX" set-journey-content "auth" "login-flow" "$STEPS2" "$OUTCOMES2" \
  --project-root="$DIR" >/dev/null
ns=$(jq '.domains.auth.journeys["login-flow"].steps | length' "$F")
no=$(jq '.domains.auth.journeys["login-flow"].outcomes | length' "$F")
[ "$ns" = "3" ] && [ "$no" = "1" ] \
  && ok "4.1 refactor replaces content" || ko "4.1" "ns=$ns no=$no"

# 5. Submode split — source + N new drafts coexist
bash "$TAX" draft-journey "auth" "signup-email" "Signup via email" --project-root="$DIR" >/dev/null
bash "$TAX" draft-journey "auth" "signup-oauth" "Signup via OAuth" --project-root="$DIR" >/dev/null
ncs=$(jq '.domains.auth.journeys | length' "$F")
[ "$ncs" = "3" ] && ok "5.1 split keeps source + adds N drafts" || ko "5.1" "ncs=$ncs"

# 6. has-journey returns 0/1 correctly
if bash "$TAX" has-journey "auth" "login-flow" --project-root="$DIR" 2>/dev/null; then
  ok "6.1 has-journey existing returns 0"
else
  ko "6.1" "returned non-zero for existing"
fi
if bash "$TAX" has-journey "auth" "ghost" --project-root="$DIR" 2>/dev/null; then
  ko "6.2" "returned 0 for missing"
else
  ok "6.2 has-journey missing returns non-zero"
fi

# 7. draft-journey under missing domain → error
if bash "$TAX" draft-journey "nope" "x" "X" --project-root="$DIR" 2>/dev/null; then
  ko "7.1" "wrongly accepted unknown domain"
else
  ok "7.1 rejects unknown domain"
fi

# 8. Schema validation — file with workspace + journeys (draft & synced)
bash "$TAX" set-vision "A long-enough product vision sentence for our test fixture so it passes the minimum length and is meaningful." \
  --project-root="$DIR" >/dev/null
# Promote login-flow to synced state by giving it a page_id (manual jq — taxonomy-state.sh
# doesn't expose a "promote-to-synced" helper; production path is /snap:doc-update)
tmp=$(mktemp)
jq '.domains.auth.journeys["login-flow"].state = "synced"
    | .domains.auth.journeys["login-flow"].page_id = "page-j-loginflow"' "$F" > "$tmp" && mv "$tmp" "$F"

if command -v ajv >/dev/null 2>&1; then
  if ajv validate -s "$SCHEMA" -d "$F" --spec=draft2020 --strict=false >/dev/null 2>&1; then
    ok "8.1 ajv validates draft+synced journey mix"
  else
    ko "8.1" "ajv rejected"
  fi
else
  ok "8.1 ajv not installed, skipping"
fi

trash "$DIR" 2>/dev/null || true

echo ""
echo "=== Summary ==="
echo "Passed: ${PASS}"
echo "Failed: ${FAIL}"
[ "$FAIL" -gt 0 ] && { printf '  - %s\n' "${ERRORS[@]}"; exit 1; }
exit 0
