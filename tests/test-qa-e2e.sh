#!/usr/bin/env bash
# E2E test for /qa pipeline pieces. Real Phase-1 (regression run, Playwright,
# code-reviewer-qa, developer agent) require LLM/MCP calls; we exercise the
# deterministic shell-level contracts: arg/config parsing, diff scope,
# regression scope branching + fallback, flaky-retry decision, severity gate
# (threshold + flaky verdict), qa cycle counter, retrigger gate, AC status
# echo into tickets.json, final status resolution.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROGRESS="${ROOT}/skills/_shared/update-progress.sh"
LOAD_CFG="${ROOT}/skills/_shared/load-config.sh"
SCHEMA="${ROOT}/skills/_shared/schemas/tickets.schema.json"

PASS=0
FAIL=0
ERRORS=()

ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1 — $2"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }
assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then ok "$label"; else ko "$label" "got '$actual' expected '$expected'"; fi
}

DIR=$(mktemp -d -t snap-qa-e2e-XXXXXX)
trap 'trash "$DIR" 2>/dev/null || true' EXIT

FEATURE_ID="01-auth"
FEATURE_DIR="${DIR}/.claude/product/features/${FEATURE_ID}"
mkdir -p "$FEATURE_DIR"

echo "=== /qa E2E (deterministic slices) ==="

# --- Setup: tiny git repo + tickets.json + config -------------------------
cd "$DIR" || exit 1
git init -q
git config user.email contact@bryanberger.dev
git config user.name "test"

mkdir -p src
echo "// init" > src/signup.ts
echo "// init" > src/login.ts
echo "// init" > src/verify.ts
git add -A
git commit -q -m "initial"

# Make a "developed" commit so we have a real sha + diff scope to test
echo "// signup body" >> src/signup.ts
echo "// signup test" > src/signup.test.ts
git add -A
git commit -q -m "feat(auth): Build signup form (t-001)"
T1_SHA=$(git rev-parse HEAD)

cat > "${FEATURE_DIR}/tickets.json" <<JSON
{
  "feature_id": "${FEATURE_ID}",
  "platform": "github",
  "tickets": [
    {
      "local_id":"t-001","title":"Build signup form","status":"in_review","type":"feat",
      "files":["src/signup.ts","src/signup.test.ts"],"commit_sha":"${T1_SHA}",
      "developed_at":"2026-05-09T12:00:00Z",
      "acceptance_criteria":[
        {"ac_id":"1","text":"Form renders","checked":false},
        {"ac_id":"2","text":"Email validated","checked":false}
      ]
    },
    {
      "local_id":"t-002","title":"Add login flow","status":"todo","type":"feat",
      "files":["src/login.ts"]
    }
  ]
}
JSON

cat > "${FEATURE_DIR}/meta.json" <<JSON
{"feature_id":"${FEATURE_ID}","title":"Auth","state":"in_review","updated_at":"2026-05-09T00:00:00Z"}
JSON

cat > "${DIR}/snapship.config.json" <<'JSON'
{
  "version": "1.0",
  "repository": {"platform": "github", "default_branch": "main"},
  "tickets": {"platform": "github"},
  "testing": {"test_command": "echo no-op"},
  "qa": {
    "qa_cycles_max": 2,
    "auto_apply_qa_feedback": true,
    "severity_threshold": "minor",
    "retrigger_review": false,
    "regression": {"enabled": true, "scope": "impacted"},
    "wireframe_check": {"enabled": false, "diff_threshold_pct": 5}
  }
}
JSON

# --- step-00 target resolution + diff scope -------------------------------
echo ""
echo "[step-00] target resolution + diff scope"

# Resolve in_review tickets
in_review=$(jq -r '[.tickets[] | select(.status=="in_review") | .local_id] | join(",")' \
  "${FEATURE_DIR}/tickets.json")
assert_eq "00.1 in_review tickets" "t-001" "$in_review"

# Diff scope — git diff-tree mirroring step-00
files=$(git diff-tree --no-commit-id --name-only -r "$T1_SHA" | sort | paste -sd, -)
assert_eq "00.2 diff scope from sha" "src/signup.test.ts,src/signup.ts" "$files"

# Ticket has commit_sha — preflight pass
sha=$(jq -r '.tickets[] | select(.local_id=="t-001").commit_sha' "${FEATURE_DIR}/tickets.json")
[ -n "$sha" ] && [ "$sha" != "null" ] \
  && ok "00.3 preflight: t-001 has commit_sha" || ko "00.3" "no sha"

# --- step-01 regression scope branching -----------------------------------
echo ""
echo "[step-01] regression scope branching"

cfg_out=$(bash "$LOAD_CFG" --project-root="$DIR" 2>/dev/null)
scope=$(echo "$cfg_out" | jq -r '.qa.regression.scope')
assert_eq "01.1 config scope=impacted" "impacted" "$scope"

# 'impacted' selects test files from changed-files-derived flows.
# Simulated flows JSON (graph would return this):
flows_json='{"flows":[{"name":"signup","files":["src/signup.ts","src/signup.test.ts"]}]}'
test_files=$(echo "$flows_json" | jq -r '.flows[].files[]' \
  | grep -E '\.(test|spec)\.[jt]sx?$' | sort -u | paste -sd, -)
assert_eq "01.2 impacted → test files only" "src/signup.test.ts" "$test_files"

# Graph unavailable → fallback to tests-only.
# tests-only: every test file that imports a changed file (depth=2 heuristic).
# Build fixture importing signup.ts.
echo "import './signup'" > src/signup.test.ts
# Heuristic from step-01: grep test files that mention any changed module.
fallback_tests=$(grep -lE "from.*signup|import.*signup" src/*.test.* 2>/dev/null | sort | paste -sd, -)
assert_eq "01.3 tests-only fallback" "src/signup.test.ts" "$fallback_tests"

# 'full' scope shells the test_command directly.
test_cmd=$(echo "$cfg_out" | jq -r '.testing.test_command')
assert_eq "01.4 test_command resolved" "echo no-op" "$test_cmd"

# Wireframe block present even when disabled (so step-02 sees enabled=false)
wf_enabled=$(echo "$cfg_out" | jq -r '.qa.wireframe_check.enabled')
assert_eq "01.5 wireframe disabled by default" "false" "$wf_enabled"

# --- step-01 flaky retry decision -----------------------------------------
echo ""
echo "[step-01] flaky retry"

# Decision: exit_code != 0 AND failures <= 3 → retry once.
should_retry() {
  local rc="$1" failures="$2"
  if [ "$rc" -ne 0 ] && [ "$failures" -le 3 ]; then echo true; else echo false; fi
}
assert_eq "01.6 rc=1 failures=2 → retry"  "true"  "$(should_retry 1 2)"
assert_eq "01.7 rc=1 failures=8 → no retry" "false" "$(should_retry 1 8)"
assert_eq "01.8 rc=0 → no retry"            "false" "$(should_retry 0 0)"

# Retry passes → retried_for_flake=true, treat overall as pass.
retry_rc=0
if [ "$retry_rc" -eq 0 ]; then
  retried_for_flake=true; verdict="pass"
else
  retried_for_flake=false; verdict="fail"
fi
assert_eq "01.9 retry pass → retried_for_flake" "true" "$retried_for_flake"
assert_eq "01.10 retry pass → overall pass"     "pass" "$verdict"

# --- step-02 severity gate (threshold + flaky verdict) --------------------
echo ""
echo "[step-02] severity gate"

severity_rank() {
  case "$1" in
    none|"") echo 0 ;;
    info) echo 1 ;;
    minor) echo 2 ;;
    major) echo 3 ;;
    critical) echo 4 ;;
    *) echo 0 ;;
  esac
}

sev_thr=$(echo "$cfg_out" | jq -r '.qa.severity_threshold')
assert_eq "02.1 threshold=minor" "minor" "$sev_thr"

# Gate: skip step-03 if severity < threshold AND flaky_verdict != real.
gate_skip() {
  local sev="$1" flaky="$2" thr="$3"
  local sr; sr=$(severity_rank "$sev")
  local tr; tr=$(severity_rank "$thr")
  if [ "$sr" -lt "$tr" ] && [ "$flaky" != "real" ]; then echo skip; else echo fix; fi
}
assert_eq "02.2 info+flaky → skip"      "skip" "$(gate_skip info flaky minor)"
assert_eq "02.3 minor+real → fix"       "fix"  "$(gate_skip minor real minor)"
assert_eq "02.4 major+real → fix"       "fix"  "$(gate_skip major real minor)"
assert_eq "02.5 info+real → fix (real gates regardless of severity)" "fix" "$(gate_skip info real minor)"
assert_eq "02.6 critical anything → fix" "fix" "$(gate_skip critical inconclusive minor)"

# --- step-02 AC status echo into tickets.json ------------------------------
echo ""
echo "[step-02] AC status echo"

ac_status='[{"ac_id":"1","status":"pass"},{"ac_id":"2","status":"fail"}]'
lid="t-001"
jq --arg lid "$lid" --argjson ac "$ac_status" '
  (.tickets[] | select(.local_id == $lid)).acceptance_criteria as $current
  | (.tickets[] | select(.local_id == $lid)).acceptance_criteria
    |= [
      range(0; ($current | length)) as $i
      | $current[$i] + {checked: ($ac[$i].status == "pass")}
    ]
' "${FEATURE_DIR}/tickets.json" > "${FEATURE_DIR}/tickets.tmp" \
  && mv "${FEATURE_DIR}/tickets.tmp" "${FEATURE_DIR}/tickets.json"

ac1=$(jq -r '.tickets[] | select(.local_id=="t-001").acceptance_criteria[0].checked' \
  "${FEATURE_DIR}/tickets.json")
ac2=$(jq -r '.tickets[] | select(.local_id=="t-001").acceptance_criteria[1].checked' \
  "${FEATURE_DIR}/tickets.json")
assert_eq "02.7 AC#1 pass → checked=true"  "true"  "$ac1"
assert_eq "02.8 AC#2 fail → checked=false" "false" "$ac2"

# Text not mutated
ac1_text=$(jq -r '.tickets[] | select(.local_id=="t-001").acceptance_criteria[0].text' \
  "${FEATURE_DIR}/tickets.json")
assert_eq "02.9 AC text preserved" "Form renders" "$ac1_text"

# --- step-03 cycle counter + termination -----------------------------------
echo ""
echo "[step-03] cycle counter"

qa_cycles_max=$(echo "$cfg_out" | jq '.qa.qa_cycles_max')
assert_eq "03.1 qa_cycles_max=2" "2" "$qa_cycles_max"

# Termination logic: continue if cycles_used < max AND severity >= threshold AND verdict=real.
cycle_decision() {
  local cycles="$1" sev="$2" verdict="$3" max="$4" thr="$5"
  local sr; sr=$(severity_rank "$sev")
  local tr; tr=$(severity_rank "$thr")
  if [ "$cycles" -ge "$max" ]; then echo blocked; return; fi
  if [ "$sr" -lt "$tr" ] && [ "$verdict" != "real" ]; then echo "done"; return; fi
  if [ "$verdict" = "flaky" ]; then echo "done"; return; fi
  echo continue
}
assert_eq "03.2 cycles=0 major real → continue" "continue" "$(cycle_decision 0 major real 2 minor)"
assert_eq "03.3 cycles=2 major real → blocked"  "blocked"  "$(cycle_decision 2 major real 2 minor)"
assert_eq "03.4 cycles=1 info flaky → done"     "done"     "$(cycle_decision 1 info flaky 2 minor)"
assert_eq "03.5 cycles=1 minor real → continue" "continue" "$(cycle_decision 1 minor real 2 minor)"

# Persist cycle state on ticket
jq --arg lid "t-001" --argjson c 1 --arg sev "minor" --arg verdict "real" \
  '(.tickets[] | select(.local_id == $lid))
     |= (.qa_cycles_used = $c
         | .qa_last_severity = $sev
         | .qa_last_flaky_verdict = $verdict)' \
  "${FEATURE_DIR}/tickets.json" > "${FEATURE_DIR}/tickets.tmp" \
  && mv "${FEATURE_DIR}/tickets.tmp" "${FEATURE_DIR}/tickets.json"

cyc=$(jq -r '.tickets[] | select(.local_id=="t-001").qa_cycles_used' \
  "${FEATURE_DIR}/tickets.json")
assert_eq "03.6 qa_cycles_used persisted" "1" "$cyc"

# --- step-04 retrigger gate -----------------------------------------------
echo ""
echo "[step-04] retrigger gate"

retrigger_default=$(echo "$cfg_out" | jq '.qa.retrigger_review')
assert_eq "04.1 retrigger default=false" "false" "$retrigger_default"

# Gate: run iff (config retrigger=true OR --retrigger flag) AND cycles>0 AND not blocked AND not already retriggered.
should_retrigger() {
  local cfg="$1" flag="$2" cycles="$3" blocked="$4" already="$5"
  if [ "$cfg" != "true" ] && [ "$flag" != "true" ]; then echo skip; return; fi
  if [ "$cycles" -eq 0 ]; then echo skip; return; fi
  if [ "$blocked" = "true" ]; then echo skip; return; fi
  if [ "$already" = "true" ]; then echo skip; return; fi
  echo run
}
assert_eq "04.2 default off → skip"             "skip" "$(should_retrigger false false 1 false false)"
assert_eq "04.3 flag on, cycles>0, ok → run"    "run"  "$(should_retrigger false true  1 false false)"
assert_eq "04.4 flag on, cycles=0 → skip"       "skip" "$(should_retrigger false true  0 false false)"
assert_eq "04.5 flag on, blocked → skip"        "skip" "$(should_retrigger false true  1 true  false)"
assert_eq "04.6 flag on, already → skip"        "skip" "$(should_retrigger false true  1 false true)"
assert_eq "04.7 cfg on, cycles>0 → run"         "run"  "$(should_retrigger true  false 1 false false)"

# Severity aggregation across 3 reviewers (max).
agg_severity() {
  local s1="$1" s2="$2" s3="$3"
  local r1; r1=$(severity_rank "$s1")
  local r2; r2=$(severity_rank "$s2")
  local r3; r3=$(severity_rank "$s3")
  local m=$r1
  [ "$r2" -gt "$m" ] && m=$r2
  [ "$r3" -gt "$m" ] && m=$r3
  case "$m" in
    0) echo none ;; 1) echo info ;; 2) echo minor ;;
    3) echo major ;; 4) echo critical ;;
  esac
}
assert_eq "04.8 max(none,minor,info)=minor"        "minor"    "$(agg_severity none minor info)"
assert_eq "04.9 max(none,none,critical)=critical"  "critical" "$(agg_severity none none critical)"
assert_eq "04.10 max(none,none,none)=none"         "none"     "$(agg_severity none none none)"

# --- step-05 final status resolution --------------------------------------
echo ""
echo "[step-05] final status"

# Resolution: blocked OR (severity >= threshold) OR flaky=real → blocked, else qa-validated
resolve_status() {
  local blocked="$1" sev="$2" flaky="$3" thr="$4"
  if [ "$blocked" = "true" ]; then echo blocked; return; fi
  local sr; sr=$(severity_rank "$sev")
  local tr; tr=$(severity_rank "$thr")
  if [ "$sr" -lt "$tr" ] && [ "$flaky" != "real" ]; then echo qa-validated; else echo blocked; fi
}
assert_eq "05.1 blocked flag → blocked"        "blocked"      "$(resolve_status true  none flaky minor)"
assert_eq "05.2 info+flaky+ok → qa-validated"  "qa-validated" "$(resolve_status false info flaky minor)"
assert_eq "05.3 minor+real → blocked"          "blocked"      "$(resolve_status false minor real minor)"
assert_eq "05.4 none+real → blocked (real)"    "blocked"      "$(resolve_status false none real minor)"
assert_eq "05.5 info+real_below_thr → blocked" "blocked"      "$(resolve_status false info real minor)"

# Update ticket → qa-validated, set timestamp
jq --arg lid "t-001" --arg s "qa-validated" \
   --arg now "2026-05-09T18:00:00Z" '
  (.tickets[] | select(.local_id == $lid))
    |= (.status = $s
        | .qa_validated_at = (if $s == "qa-validated" then $now else null end))
' "${FEATURE_DIR}/tickets.json" > "${FEATURE_DIR}/tickets.tmp" \
  && mv "${FEATURE_DIR}/tickets.tmp" "${FEATURE_DIR}/tickets.json"

new_status=$(jq -r '.tickets[] | select(.local_id=="t-001").status' \
  "${FEATURE_DIR}/tickets.json")
assert_eq "05.6 status=qa-validated"      "qa-validated"          "$new_status"
new_ts=$(jq -r '.tickets[] | select(.local_id=="t-001").qa_validated_at' \
  "${FEATURE_DIR}/tickets.json")
assert_eq "05.7 qa_validated_at set"      "2026-05-09T18:00:00Z"  "$new_ts"

# Schema still valid post-mutation
if command -v ajv >/dev/null 2>&1; then
  if ajv validate -s "$SCHEMA" -d "${FEATURE_DIR}/tickets.json" \
      --spec=draft2020 --strict=false >/dev/null 2>&1; then
    ok "05.8 tickets.json valid post-validate"
  else
    ko "05.8" "ajv rejected"
  fi
else
  echo "  SKIP  05.8 ajv not installed"
fi

# --- progress.md entries --------------------------------------------------
echo ""
echo "[progress] entries"
bash "$PROGRESS" --project-root="$DIR" --feature-id="$FEATURE_ID" \
  --skill=qa --step-num=00 --step-name=init --status=ok >/dev/null
bash "$PROGRESS" --project-root="$DIR" --feature-id="$FEATURE_ID" \
  --skill=qa --step-num=01 --step-name=collect --status=ok --note="regression=pass" >/dev/null
bash "$PROGRESS" --project-root="$DIR" --feature-id="$FEATURE_ID" \
  --skill=qa --step-num=02 --step-name=interpret --status=ok --note="severity=minor" >/dev/null
bash "$PROGRESS" --project-root="$DIR" --feature-id="$FEATURE_ID" \
  --skill=qa --step-num=03 --step-name=fix --status=ok --note="t-001 cycles=1" >/dev/null
bash "$PROGRESS" --project-root="$DIR" --feature-id="$FEATURE_ID" \
  --skill=qa --step-num=05 --step-name=finish --status=ok --note="validated=1" >/dev/null

prog="${FEATURE_DIR}/progress.md"
for step in init collect interpret fix finish; do
  if grep -qE "qa step-[0-9]+ ${step} — ok" "$prog"; then
    ok "progress contains qa ${step} ok"
  else
    ko "progress qa ${step}" "missing"
  fi
done

# --- Summary --------------------------------------------------------------
echo ""
echo "=== Summary ==="
echo "Passed: ${PASS}"
echo "Failed: ${FAIL}"

if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "Errors:"
  printf '  - %s\n' "${ERRORS[@]+"${ERRORS[@]}"}"
  exit 1
fi
