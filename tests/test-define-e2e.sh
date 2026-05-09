#!/usr/bin/env bash
# E2E for /define skill — exercises the helper-script orchestration end-to-end
# without the AskUserQuestion model loop. Greenfield + extension paths.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DETECT="${ROOT}/skills/_shared/detect-codebase.sh"
STATE="${ROOT}/skills/_shared/define-state.sh"
PROGRESS="${ROOT}/skills/_shared/update-progress.sh"
RESUME="${ROOT}/skills/_shared/resume-state.sh"
LOAD_CONFIG="${ROOT}/skills/_shared/load-config.sh"

PASS=0
FAIL=0
ERRORS=()

ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }
setup_dir() { mktemp -d -t artysan-e2e-XXXXXX; }

write_config_none() {
  local d="$1"
  cat > "${d}/artysan.config.json" <<'JSON'
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

# config + scaffold
write_config_none "$DIR"
mkdir -p "$DIR/.claude/product/features"

# load-config materializes resolved config
out=$(bash "$LOAD_CONFIG" --project-root="$DIR" 2>/dev/null)
if echo "$out" | jq -e '.documentation.platform == "none"' >/dev/null 2>&1; then
  ok "1.2 load-config resolves platform=none"
else
  ko "1.2 load-config did not resolve platform"
fi

# step-00: init state, log progress
bash "$STATE" init --lang=en --mode=greenfield --project-root="$DIR" >/dev/null
[ -f "$DIR/.claude/product/.define-state.json" ] && ok "1.3 state file created" || ko "1.3"
bash "$PROGRESS" --project-root="$DIR" --feature-id=_global --step-num=00 --step-name=init --status=ok --skill=define >/dev/null

# step-01: vision + north star
bash "$STATE" set vision "Build a tool that helps designers ship wireframes faster by automating handoff." --project-root="$DIR"
bash "$STATE" set north_star_metric "weekly_active_designers" --project-root="$DIR"
bash "$STATE" set north_star_current "0" --project-root="$DIR"
bash "$STATE" set north_star_target "100" --project-root="$DIR"
bash "$STATE" set target_horizon "Q3 2026" --project-root="$DIR"
bash "$PROGRESS" --project-root="$DIR" --feature-id=_global --step-num=01 --step-name=vision --status=ok --skill=define >/dev/null

# step-02: persona
bash "$STATE" add-persona '{
  "persona_name": "Sarah",
  "persona_role": "Freelance product designer",
  "persona_goals": "Ship faster, reduce dev handoff friction",
  "persona_pains": "Manual ticket-by-ticket wireframe descriptions",
  "persona_tools": "Figma, Notion"
}' --project-root="$DIR"
bash "$PROGRESS" --project-root="$DIR" --feature-id=_global --step-num=02 --step-name=personas --status=ok --skill=define >/dev/null

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
bash "$PROGRESS" --project-root="$DIR" --feature-id=_global --step-num=03 --step-name=features --status=ok --skill=define >/dev/null

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
platform=$(jq -r '.documentation.platform' "$DIR/artysan.config.json")
if [ "$platform" = "none" ]; then
  bash "$PROGRESS" --project-root="$DIR" --feature-id=_global --step-num=05 --step-name=publish --status=skip --skill=define --note="documentation.platform=none" >/dev/null
  ok "1.7 step-05 skipped on platform=none"
else
  ko "1.7 platform should be none"
fi

# resume after terminal: should compute step-06 (past terminal)
out=$(bash "$RESUME" next --skill=define --project-root="$DIR")
ns=$(echo "$out" | jq -r '.next_step')
[ "$ns" = "step-06" ] && ok "1.8 resume past skip points to step-06 (caller stops)" || ko "1.8 got $ns"

# progress.md contains the full happy-path
if grep -q "define step-00 init — ok" "$DIR/.claude/product/progress.md" \
  && grep -q "define step-03 features — ok" "$DIR/.claude/product/progress.md" \
  && grep -q "define step-05 publish — skip" "$DIR/.claude/product/progress.md"; then
  ok "1.9 progress.md captures full pipeline"
else
  ko "1.9 progress.md missing entries"
fi

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

# Pre-existing PRD + state from prior run
mkdir -p "$DIR/.claude/product/features/01-auth"
echo "# PRD — TestProduct" > "$DIR/.claude/product/prd-global.md"
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

# Per-feature progress (extension scenario advances per-feature)
bash "$PROGRESS" --project-root="$DIR" --feature-id=02-billing --step-num=03 --step-name=features --status=ok --skill=define >/dev/null

# Resume with partial-match feature
out=$(bash "$RESUME" next --skill=define --feature=02 --project-root="$DIR")
fid=$(echo "$out" | jq -r '.feature_id')
ns=$(echo "$out" | jq -r '.next_step')
[ "$fid" = "02-billing" ] && ok "2.2 partial '02' resolves to 02-billing" || ko "2.2 got $fid"
[ "$ns" = "step-04" ] && ok "2.3 next_step=step-04 from per-feature progress" || ko "2.3 got $ns"

# Resume slug partial
out=$(bash "$RESUME" next --skill=define --feature=bill --project-root="$DIR")
fid=$(echo "$out" | jq -r '.feature_id')
[ "$fid" = "02-billing" ] && ok "2.4 'bill' resolves to 02-billing" || ko "2.4 got $fid"

# Validate full state
if bash "$STATE" validate --project-root="$DIR" 2>/tmp/define-e2e-validate.err; then
  ok "2.5 extension state validates"
else
  ko "2.5 validation failed: $(cat /tmp/define-e2e-validate.err)"
fi

# Wipe (step-05 cleanup) preserves docs cache + per-feature progress, removes state
echo '{"prd_global":{"page_id":"abc","url":"u"}}' > "$DIR/.claude/product/.docs-cache.json"
bash "$STATE" wipe --project-root="$DIR" >/dev/null
[ ! -f "$DIR/.claude/product/.define-state.json" ] && ok "2.6 wipe removed state file" || ko "2.6"
[ -f "$DIR/.claude/product/.docs-cache.json" ] && ok "2.7 wipe preserved docs-cache" || ko "2.7"
[ -f "$DIR/.claude/product/features/02-billing/progress.md" ] && ok "2.8 wipe preserved per-feature progress.md" || ko "2.8"

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
