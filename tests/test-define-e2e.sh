#!/usr/bin/env bash
# E2E for /define skill — exercises the helper-script orchestration end-to-end
# without the AskUserQuestion model loop. Greenfield + extension paths.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DETECT="${ROOT}/skills/_shared/detect-codebase.sh"
STATE="${ROOT}/skills/_shared/define-state.sh"
PROGRESS="${ROOT}/skills/_shared/progress.sh"
SETUP="${ROOT}/skills/_shared/setup-snap-dir.sh"
LOAD_CONFIG="${ROOT}/skills/_shared/load-config.sh"

PASS=0
FAIL=0
ERRORS=()

ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }
setup_dir() { mktemp -d -t snap-e2e-XXXXXX; }

write_config_none() {
  local d="$1"
  cat > "${d}/snap.config.json" <<'JSON'
{
  "version": "1.0",
  "documentation": { "platform": "none" },
  "repository": { "platform": "github", "default_branch": "main" },
  "tickets": { "platform": "github" }
}
JSON
}

# ============================================================================
# E2E #1 — greenfield path
# ============================================================================
echo "=== E2E #1: greenfield ==="
DIR=$(setup_dir)

# step-00: detect codebase (empty dir → false)
echo "[1] detect-codebase"
verdict=$(bash "$DETECT" --project-root="$DIR")
hc=$(echo "$verdict" | jq -r '.has_codebase')
[ "$hc" = "false" ] && ok "1.1 has_codebase=false on empty dir" || ko "1.1 got $hc"

# config + scaffold via setup-snap-dir.sh (v1.0.0 layout)
write_config_none "$DIR"
bash "$SETUP" --project-root="$DIR" >/dev/null
[ -d "$DIR/.snap/manifests" ] && [ -d "$DIR/.snap/queues" ] \
  && ok "1.1b setup-snap-dir scaffolded v1.0 layout" \
  || ko "1.1b layout missing"

# load-config materializes resolved config
out=$(bash "$LOAD_CONFIG" --project-root="$DIR" 2>/dev/null)
if echo "$out" | jq -e '.documentation.platform == "none"' >/dev/null 2>&1; then
  ok "1.2 load-config resolves platform=none"
else
  ko "1.2 load-config did not resolve platform"
fi

# step-00: init state, log progress
bash "$STATE" init --lang=en --mode=greenfield --project-root="$DIR" >/dev/null
[ -f "$DIR/.snap/.define-state.json" ] && ok "1.3 state file created" || ko "1.3"
bash "$PROGRESS" step --project-root="$DIR" --skill=define --feature-id=_global \
  --step-num=00 --step-name=init --status=ok >/dev/null

# step-01: vision + north star
bash "$STATE" set vision "Build a tool that helps designers ship wireframes faster by automating handoff." --project-root="$DIR"
bash "$STATE" set north_star_metric "weekly_active_designers" --project-root="$DIR"
bash "$STATE" set north_star_current "0" --project-root="$DIR"
bash "$STATE" set north_star_target "100" --project-root="$DIR"
bash "$STATE" set target_horizon "Q3 2026" --project-root="$DIR"
bash "$PROGRESS" step --project-root="$DIR" --skill=define --feature-id=_global \
  --step-num=01 --step-name=vision --status=ok >/dev/null

# step-02: persona
bash "$STATE" add-persona '{
  "persona_name": "Sarah",
  "persona_role": "Freelance product designer",
  "persona_goals": "Ship faster, reduce dev handoff friction",
  "persona_pains": "Manual ticket-by-ticket wireframe descriptions",
  "persona_tools": "Figma, Notion"
}' --project-root="$DIR"
bash "$PROGRESS" step --project-root="$DIR" --skill=define --feature-id=_global \
  --step-num=02 --step-name=personas --status=ok >/dev/null

# step-03: feature
bash "$STATE" add-feature '{
  "feature_id": "01-auth",
  "feature_title": "Email signup",
  "feature_status": "refined",
  "priority": "must",
  "problem_statement": "Designers cannot save their work between sessions without an account.",
  "solution_overview": "Add email/password signup with verification email.",
  "acceptance_criteria": [{"ac_id":"1","ac_text":"User signs up with email + password"},{"ac_id":"2","ac_text":"Verification email sent"}],
  "in_scope": "email/password, verification email",
  "out_of_scope": "OAuth, SSO, MFA",
  "wireframes": []
}' --project-root="$DIR"
bash "$PROGRESS" step --project-root="$DIR" --skill=define --feature-id=_global \
  --step-num=03 --step-name=features --status=ok >/dev/null

# step-03 validate
if bash "$STATE" validate --project-root="$DIR" 2>/tmp/define-e2e-validate.err; then
  ok "1.4 state validates after step-03"
else
  ko "1.4 validation failed: $(cat /tmp/define-e2e-validate.err)"
fi

# step-04 (render): not implemented in bash; verify state has everything renderer needs
v=$(bash "$STATE" get vision --project-root="$DIR")
[ -n "$v" ] && ok "1.5 vision retrievable for render" || ko "1.5"
fcount=$(bash "$STATE" list-features --project-root="$DIR" | wc -l | tr -d ' ')
[ "$fcount" = "1" ] && ok "1.6 features list yields 1 entry" || ko "1.6 got $fcount"

# step-05 publish: platform=none → skip
platform=$(jq -r '.documentation.platform' "$DIR/snap.config.json")
if [ "$platform" = "none" ]; then
  bash "$PROGRESS" step --project-root="$DIR" --skill=define --feature-id=_global \
    --step-num=05 --step-name=publish --status=skip --note="documentation.platform=none" >/dev/null
  ok "1.7 step-05 skipped on platform=none"
else
  ko "1.7 platform should be none"
fi

# Finish run → entry purged from in_flight.
bash "$PROGRESS" finish --project-root="$DIR" --skill=define --feature-id=_global --status=ok >/dev/null

# resume after terminal: skill purged from in_flight → empty stdout
out=$(bash "$PROGRESS" resume --project-root="$DIR" --skill=define --feature-id=_global)
if [ -z "$out" ]; then
  ok "1.8 resume after terminal returns empty (purged)"
else
  ko "1.8 expected empty, got '$out'"
fi

# progress.json captures the full happy-path (steps inspected before finish purge: list returns []
# after finish ok; assert steps were appended during run via a second probe scenario).
# Cross-check: list a fresh skill run after init to confirm steps land in the JSON.
bash "$PROGRESS" start --project-root="$DIR" --skill=define --feature-id=_global >/dev/null
bash "$PROGRESS" step --project-root="$DIR" --skill=define --feature-id=_global \
  --step-num=00 --step-name=init --status=ok >/dev/null
bash "$PROGRESS" step --project-root="$DIR" --skill=define --feature-id=_global \
  --step-num=03 --step-name=features --status=ok >/dev/null
steps_json=$(bash "$PROGRESS" list --project-root="$DIR" \
  | jq '.[] | select(.skill == "define" and .feature_id == "_global") | .steps')
init_ok=$(echo "$steps_json" | jq '[.[] | select(.name == "init" and .status == "ok")] | length')
feat_ok=$(echo "$steps_json" | jq '[.[] | select(.name == "features" and .status == "ok")] | length')
if [ "$init_ok" -ge 1 ] && [ "$feat_ok" -ge 1 ]; then
  ok "1.9 progress.json captures full pipeline"
else
  ko "1.9 progress.json missing entries (init=$init_ok features=$feat_ok)"
fi
bash "$PROGRESS" finish --project-root="$DIR" --skill=define --feature-id=_global --status=ok >/dev/null

trash "$DIR" 2>/dev/null || true

# ============================================================================
# E2E #2 — extension path (existing project + new feature)
# ============================================================================
echo ""
echo "=== E2E #2: extension ==="
DIR=$(setup_dir)
write_config_none "$DIR"

# Simulate existing codebase
(
  cd "$DIR" || exit
  echo '{"name":"existing","version":"1.0.0"}' > package.json
  mkdir -p src
  echo "console.log('hi');" > src/index.js
  git init -q
  git config user.email "test@test"
  git config user.name "test"
  git add package.json src/index.js
  git commit -m init -q
)

verdict=$(bash "$DETECT" --project-root="$DIR")
hc=$(echo "$verdict" | jq -r '.has_codebase')
[ "$hc" = "true" ] && ok "2.1 has_codebase=true on existing project" || ko "2.1 got $hc"

# Scaffold v1.0 workspace + per-feature manifest (extension uses --feature)
bash "$SETUP" --project-root="$DIR" --feature-id=02-billing --feature-name="Billing" --lang=en >/dev/null
[ -f "$DIR/.snap/manifests/02-billing.manifest.json" ] \
  && ok "2.1b extension manifest created" \
  || ko "2.1b manifest missing"

bash "$STATE" init --lang=en --mode=extension --feature=02-billing --project-root="$DIR" >/dev/null
bash "$STATE" set vision "Existing product description that is long enough and contains a verb." --project-root="$DIR"
bash "$STATE" set north_star_metric "wad" --project-root="$DIR"
bash "$STATE" set north_star_current "10" --project-root="$DIR"
bash "$STATE" set north_star_target "200" --project-root="$DIR"
bash "$STATE" set target_horizon "2026-Q4" --project-root="$DIR"
bash "$STATE" add-persona '{"persona_name":"X","persona_role":"r","persona_goals":"g","persona_pains":"p","persona_tools":"t"}' --project-root="$DIR"
bash "$STATE" add-feature '{
  "feature_id":"02-billing","feature_title":"Billing","feature_status":"refined","priority":"must",
  "problem_statement":"Users cannot pay for the service yet, blocking monetisation.",
  "solution_overview":"Stripe checkout integration.",
  "acceptance_criteria":[{"ac_id":"1","ac_text":"Stripe checkout works"}],
  "in_scope":"Stripe","out_of_scope":"Other gateways","wireframes":[]
}' --project-root="$DIR"

# Per-feature progress: log step-03 fail (so resume has something to surface)
bash "$PROGRESS" step --project-root="$DIR" --skill=define --feature-id=02-billing \
  --step-num=03 --step-name=features --status=fail --note="simulated mid-run interrupt" >/dev/null

# Resume with exact feature_id → tab-separated NUM\tNAME\tSTATUS (progress.sh contract)
out=$(bash "$PROGRESS" resume --project-root="$DIR" --skill=define --feature-id=02-billing)
if [ -n "$out" ]; then
  num=$(echo "$out" | awk -F'\t' '{print $1}')
  name=$(echo "$out" | awk -F'\t' '{print $2}')
  status=$(echo "$out" | awk -F'\t' '{print $3}')
  [ "$num" = "03" ] && ok "2.2 resume returns step-num=03" || ko "2.2 got num=$num"
  [ "$name" = "features" ] && ok "2.3 resume returns step-name=features" || ko "2.3 got $name"
  [ "$status" = "fail" ] && ok "2.4 resume returns status=fail" || ko "2.4 got $status"
else
  ko "2.2/2.3/2.4 resume returned empty" "expected resumable step"
fi

# Manifest exists for the feature → skill layer can match partial '02' against
# .snap/manifests/02-billing.manifest.json (partial-match lives in step-00, not helper)
matches=$(ls "$DIR/.snap/manifests"/02-*.manifest.json 2>/dev/null | wc -l | tr -d ' ')
[ "$matches" = "1" ] && ok "2.5a partial-match candidate set has 1 manifest for '02'" \
  || ko "2.5a got $matches manifests"

# Validate full state
if bash "$STATE" validate --project-root="$DIR" 2>/tmp/define-e2e-validate.err; then
  ok "2.5 extension state validates"
else
  ko "2.5 validation failed: $(cat /tmp/define-e2e-validate.err)"
fi

# Wipe (step-05 cleanup) deletes define-state but leaves manifests + progress.json intact
bash "$STATE" wipe --project-root="$DIR" >/dev/null
[ ! -f "$DIR/.snap/.define-state.json" ] && ok "2.6 wipe removed define-state" || ko "2.6"
[ -f "$DIR/.snap/manifests/02-billing.manifest.json" ] \
  && ok "2.7 wipe preserved per-feature manifest" \
  || ko "2.7 manifest gone"
[ -f "$DIR/.snap/progress.json" ] \
  && ok "2.8 wipe preserved progress.json" \
  || ko "2.8 progress.json gone"

trash "$DIR" 2>/dev/null || true

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
