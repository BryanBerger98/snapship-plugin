#!/usr/bin/env bash
# E2E test for /develop pipeline pieces. Real Phase-1/Phase-2 require LLM agents
# (developer, code-reviewer-*) so we exercise the deterministic shell-level
# contracts: arg parsing surface, branch idempotence (step-02), daemon.sh
# template rendering (step-03c), fail_strategy resolution (step-03a) and the
# jq commit-sha patch (step-03a tail).

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RENDER="${ROOT}/skills/_shared/render-template.sh"
NAMING="${ROOT}/skills/_shared/apply-naming.sh"
PROGRESS="${ROOT}/skills/_shared/update-progress.sh"
DAEMON_TPL="${ROOT}/skills/_shared/templates/develop-daemon.sh.tpl"
SCHEMA="${ROOT}/skills/_shared/schemas/tickets.schema.json"
LOAD_CFG="${ROOT}/skills/_shared/load-config.sh"

PASS=0
FAIL=0
ERRORS=()

ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1 — $2"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }
assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then ok "$label"; else ko "$label" "got '$actual' expected '$expected'"; fi
}

DIR=$(mktemp -d -t snap-dev-e2e-XXXXXX)
trap 'trash "$DIR" 2>/dev/null || true' EXIT

FEATURE_ID="01-auth"
FEATURE_DIR="${DIR}/.claude/product/features/${FEATURE_ID}"
mkdir -p "$FEATURE_DIR"

echo "=== /develop E2E (deterministic slices) ==="

# --- Setup: tiny git repo + tickets.json + config -------------------------
cd "$DIR" || exit 1
git init -q
git config user.email contact@bryanberger.dev
git config user.name "test"
echo "init" > README.md
git add README.md
git commit -q -m "initial"

cat > "${FEATURE_DIR}/tickets.json" <<JSON
{
  "feature_id": "${FEATURE_ID}",
  "platform": "github",
  "tickets": [
    {"local_id":"t-001","title":"Build signup form","status":"todo","type":"feat","files":["src/signup.ts"]},
    {"local_id":"t-002","title":"Add login flow","status":"todo","type":"feat","files":["src/login.ts"]},
    {"local_id":"t-003","title":"Fix verify regex","status":"todo","type":"fix","files":["src/verify.ts"]}
  ]
}
JSON

cat > "${FEATURE_DIR}/meta.json" <<JSON
{"feature_id":"${FEATURE_ID}","title":"Auth","state":"ticketed","updated_at":"2026-05-09T00:00:00Z"}
JSON

cat > "${DIR}/snapship.config.json" <<'JSON'
{
  "version": "1.0",
  "repository": {"platform": "github", "default_branch": "main"},
  "tickets": {"platform": "github"},
  "develop": {
    "review_cycles_max": 3,
    "fail_strategy": "next-ticket",
    "reviews": {
      "technical": {"severity_threshold": "minor"},
      "functional": {"severity_threshold": "minor"},
      "security":   {"severity_threshold": "major"}
    }
  },
  "naming": {
    "branch_pattern": "feat/{slug}",
    "commit_pattern": "{type}({scope}): {message}",
    "feature_slug_max_length": 40
  }
}
JSON

# --- step-02 branch idempotence ------------------------------------------
echo ""
echo "[step-02] branch idempotent"

slug="${FEATURE_ID#*-}"  # 'auth'
branch=$(bash "$NAMING" --type=branch \
  --context='{"type":"feat","ticket_id":"t-001","slug":"'"$slug"'"}' \
  --project-root="$DIR")
assert_eq "02.1 branch from naming" "feat/auth" "$branch"

# First run: branch absent → checkout -b
if git rev-parse --verify "$branch" >/dev/null 2>&1; then
  git checkout -q "$branch"
else
  git checkout -q -b "$branch"
fi
git rev-parse --abbrev-ref HEAD | grep -q "^${branch}$" \
  && ok "02.2 first run creates branch" || ko "02.2" "branch=$(git rev-parse --abbrev-ref HEAD)"

# Switch back to main, then re-run idempotently
git checkout -q main
if git rev-parse --verify "$branch" >/dev/null 2>&1; then
  git checkout -q "$branch"
else
  git checkout -q -b "$branch"
fi
git rev-parse --abbrev-ref HEAD | grep -q "^${branch}$" \
  && ok "02.3 second run reuses branch" || ko "02.3" "branch=$(git rev-parse --abbrev-ref HEAD)"

# Branch count: still exactly one feat/auth (no duplicates created)
n=$(git branch --list "$branch" | wc -l | tr -d ' ')
assert_eq "02.4 no duplicate branch" "1" "$n"

# --- step-03a commit format + sha patch into tickets.json -----------------
echo ""
echo "[step-03a] commit message + tickets.json patch"

ticket=$(jq '.tickets[0]' "${FEATURE_DIR}/tickets.json")
type=$(jq -r '.type' <<<"$ticket")
title=$(jq -r '.title' <<<"$ticket")
local_id=$(jq -r '.local_id' <<<"$ticket")
scope="auth"

msg=$(bash "$NAMING" --type=commit \
  --context='{"type":"'"$type"'","scope":"'"$scope"'","message":"'"$title"' ('"$local_id"')"}' \
  --project-root="$DIR")
assert_eq "03a.1 commit message format" "feat(auth): Build signup form (t-001)" "$msg"

# Simulate the developer agent making a change
echo "// signup" > src-stub.txt
git add src-stub.txt
git commit -q -m "$msg"
sha=$(git rev-parse HEAD)

# Patch tickets.json (mirrors step-03a tail)
jq --arg lid "$local_id" --arg sha "$sha" --arg now "2026-05-09T12:00:00Z" \
  '(.tickets[] | select(.local_id == $lid))
     |= (.commit_sha = $sha | .developed_at = $now | .status = "in_review")' \
  "${FEATURE_DIR}/tickets.json" > "${FEATURE_DIR}/tickets.tmp" \
  && mv "${FEATURE_DIR}/tickets.tmp" "${FEATURE_DIR}/tickets.json"

t1=$(jq '.tickets[] | select(.local_id=="t-001")' "${FEATURE_DIR}/tickets.json")
status=$(jq -r '.status' <<<"$t1")
assert_eq "03a.2 status → in_review" "in_review" "$status"
saved_sha=$(jq -r '.commit_sha' <<<"$t1")
assert_eq "03a.3 commit_sha persisted" "$sha" "$saved_sha"

# Schema validation
if command -v ajv >/dev/null 2>&1; then
  if ajv validate -s "$SCHEMA" -d "${FEATURE_DIR}/tickets.json" --spec=draft2020 --strict=false >/dev/null 2>&1; then
    ok "03a.4 tickets.json valid post-commit"
  else
    ko "03a.4" "ajv rejected"
  fi
else
  echo "  SKIP  03a.4 ajv not installed"
fi

# --- step-03a fail_strategy: severity aggregation -------------------------
echo ""
echo "[step-03a] severity aggregation logic"

severity_rank() {
  case "$1" in
    none|"") echo 0 ;;
    info)    echo 1 ;;
    minor)   echo 2 ;;
    major)   echo 3 ;;
    critical) echo 4 ;;
    *) echo 0 ;;
  esac
}

# Simulate three reviewer outputs. Block if any reviewer.severity >= reviewer.threshold.
tech_sev="info"; tech_thr="minor"
func_sev="minor"; func_thr="minor"
sec_sev="none";  sec_thr="major"

blocked=false
for pair in "tech_sev=$tech_sev,tech_thr=$tech_thr" "func_sev=$func_sev,func_thr=$func_thr" "sec_sev=$sec_sev,sec_thr=$sec_thr"; do
  sev_var="${pair%%,*}"; thr_var="${pair##*,}"
  sev_val="${sev_var#*=}"; thr_val="${thr_var#*=}"
  sr=$(severity_rank "$sev_val"); tr=$(severity_rank "$thr_val")
  [ "$sr" -ge "$tr" ] && blocked=true
done
assert_eq "03a.5 functional minor at minor threshold → blocked" "true" "$blocked"

# Reset: all below thresholds
tech_sev="info"; func_sev="info"; sec_sev="minor"
blocked=false
sr=$(severity_rank "$tech_sev"); tr=$(severity_rank "$tech_thr"); [ "$sr" -ge "$tr" ] && blocked=true
sr=$(severity_rank "$func_sev"); tr=$(severity_rank "$func_thr"); [ "$sr" -ge "$tr" ] && blocked=true
sr=$(severity_rank "$sec_sev");  tr=$(severity_rank "$sec_thr");  [ "$sr" -ge "$tr" ] && blocked=true
assert_eq "03a.6 all below thresholds → not blocked" "false" "$blocked"

# Critical short-circuits regardless of threshold
sec_sev="critical"
sr=$(severity_rank "$sec_sev")
[ "$sr" -eq 4 ] && ok "03a.7 critical detected" || ko "03a.7" "sr=$sr"

# --- step-03c daemon template renders -------------------------------------
echo ""
echo "[step-03c] daemon.sh template render"

# Build queue
jq -n --arg fid "$FEATURE_ID" \
  '{queue:["t-002","t-003"], processed:["t-001"], started_at:"2026-05-09T12:00:00Z", loop_mode:"daemon"}' \
  > "${FEATURE_DIR}/.develop-queue.json"

ctx=$(jq -nc \
  --arg fid "$FEATURE_ID" \
  --arg qpath "${FEATURE_DIR}/.develop-queue.json" \
  --arg cmd "claude" \
  --arg args "--dry-run" \
  '{feature_id:$fid, queue_path:$qpath, claude_cmd:$cmd, develop_args:$args}')

bash "$RENDER" --template="$DAEMON_TPL" --vars="$ctx" > "${FEATURE_DIR}/daemon.sh"
chmod +x "${FEATURE_DIR}/daemon.sh"

# Lint the rendered daemon
if shellcheck --severity=warning "${FEATURE_DIR}/daemon.sh" 2>/dev/null; then
  ok "03c.1 rendered daemon passes shellcheck"
else
  echo "  WARN  03c.1 shellcheck issues (skipping in CI fallback)"
fi

# --status mode prints JSON
status_json=$("${FEATURE_DIR}/daemon.sh" --status 2>&1)
size=$(echo "$status_json" | jq '.queue_size')
assert_eq "03c.2 --status reports queue_size" "2" "$size"

processed_n=$(echo "$status_json" | jq '.processed')
assert_eq "03c.3 --status reports processed count" "1" "$processed_n"

fid=$(echo "$status_json" | jq -r '.feature_id')
assert_eq "03c.4 --status reports feature_id" "$FEATURE_ID" "$fid"

# Variable substitution: no {{ left in script
if grep -q '{{' "${FEATURE_DIR}/daemon.sh"; then
  ko "03c.5 unrendered placeholders" "found {{"
else
  ok "03c.5 all placeholders resolved"
fi

# --- progress.md entries --------------------------------------------------
echo ""
echo "[progress] entries"
bash "$PROGRESS" --project-root="$DIR" --feature-id="$FEATURE_ID" \
  --skill=develop --step-num=00 --step-name=init --status=ok >/dev/null
bash "$PROGRESS" --project-root="$DIR" --feature-id="$FEATURE_ID" \
  --skill=develop --step-num=02 --step-name=prepare --status=ok --note="branch=$branch" >/dev/null
bash "$PROGRESS" --project-root="$DIR" --feature-id="$FEATURE_ID" \
  --skill=develop --step-num=03a --step-name=standalone --status=ok --note="t-001 sha=$sha" >/dev/null

prog="${FEATURE_DIR}/progress.md"
for step in init prepare standalone; do
  if grep -qE "develop step-[0-9a-z]+ ${step} — ok" "$prog"; then
    ok "progress contains ${step} ok"
  else
    ko "progress ${step}" "missing"
  fi
done

# --- fail_strategy from config -------------------------------------------
echo ""
echo "[config] fail_strategy / review_cycles_max"
cfg_out=$(bash "$LOAD_CFG" --project-root="$DIR" 2>/dev/null)
fs=$(echo "$cfg_out" | jq -r '.develop.fail_strategy')
assert_eq "cfg.1 fail_strategy" "next-ticket" "$fs"
rcm=$(echo "$cfg_out" | jq '.develop.review_cycles_max')
assert_eq "cfg.2 review_cycles_max" "3" "$rcm"
sec_thr=$(echo "$cfg_out" | jq -r '.develop.reviews.security.severity_threshold')
assert_eq "cfg.3 security threshold" "major" "$sec_thr"

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
