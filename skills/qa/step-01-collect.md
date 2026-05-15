---
step: 01-collect
next_step: 02-interpret
description: Run regression (scope=impacted/full/tests-only) + Playwright wireframe diff. Aggregate raw evidence for the reviewer.
---

# step-01 — collect

Gather raw signals — test results + wireframe diffs — without interpreting
them. step-02 hands these to the QA reviewer agent.

## A. Regression

Branch on `regression_scope`:

### `impacted` (default)

Use code-review-graph to compute affected tests:

```bash
# emit MCP descriptor (exit 10) for get_affected_flows
bash skills/_shared/check-mcp-required.sh --skill=qa --project-root="$PWD" \
  --mcp=code-review-graph
```

The MCP returns flows touching any file in the diff. Extract test files from
the flows; pass them to `test_command`:

```bash
test_files=$(echo "$flows_json" | jq -r '.flows[].files[]' \
  | grep -E '\.(test|spec)\.[jt]sx?$' | sort -u)
test_cmd=$(jq -r '.testing.test_command' <<<"$CONFIG_JSON")

if [ -n "$test_files" ]; then
  $test_cmd $test_files > .snap/queues/${feature_id}.qa-regression-${run_id}.log 2>&1
  rc=$?
else
  echo "no impacted tests" > .snap/queues/${feature_id}.qa-regression-${run_id}.log
  rc=0
fi
```

Graph unavailable → fall through to `tests-only`.

### `full`

```bash
$test_cmd > .snap/queues/${feature_id}.qa-regression-${run_id}.log 2>&1
rc=$?
```

### `tests-only`

```bash
# Heuristic: every test file that imports any changed file (transitively, depth=2).
test_files=$(grep -lE 'from.*\b(signup|login)' src/**/*.test.* 2>/dev/null || true)
$test_cmd $test_files > .snap/queues/${feature_id}.qa-regression-${run_id}.log 2>&1
rc=$?
```

Persist `regression: {scope, exit_code, log_path, retried_for_flake}` per
ticket in `.snap/queues/${feature_id}.qa-collect-${run_id}.json`.

## B. Wireframe diff (Playwright)

Skip if `wireframe_enabled=false` or the ticket has no `wireframe_url`.

```bash
# Discover the route to render. Convention: ticket.files[0] under pages/ →
# derive URL from path, else AskUserQuestion.
route=$(echo "$files" | grep -E '^(src/)?(pages|app|routes)/' | head -1 | \
  sed -E 's|.*/(pages\|app\|routes)/||; s|\.[a-z]+$||; s|^index$||')

# emit MCP descriptor (exit 10) for Playwright
# - launch headless, navigate to local dev server (started by ticket.dev_command or default)
# - screenshot at viewport 1440x900 + 390x844
```

Compare the screenshots to the cached Frame0 PNGs at
`.snap/wireframes/${feature_id}/${screen_id}-${state}.png`:

```bash
# structural-diff: pixel-diff after edge detection (resilient to colour drift).
# Use perceptual lib (e.g. 'pixelmatch' via npx) — descriptor-emit so user/IDE
# runs it. Threshold from config.qa.wireframe_check.diff_threshold_pct.
```

Persist `wireframe: {screen_id, diff_pct, threshold_pct, png_local, png_ref}`.

## C. Flaky retry (regression only)

If `regression.exit_code != 0` AND failures are limited to <=3 tests, retry
**once**:

```bash
$test_cmd $failed_tests > .snap/queues/${feature_id}.qa-regression-${run_id}-retry.log 2>&1
```

If retry passes → mark `retried_for_flake=true` and treat overall regression
as `pass` (the reviewer in step-02 sees both runs and rules on flake-vs-real).

## D. Aggregate evidence

Final `.snap/queues/${feature_id}.qa-collect-${run_id}.json`:

```json
{
  "ticket_id": "t-001",
  "regression": {"scope":"impacted","exit_code":0,"log_path":"...","retried_for_flake":false},
  "wireframe":  {"enabled":true,"screen_id":"signup-screen","diff_pct":2.1,"threshold_pct":5}
}
```

## Telemetry + progress

```bash
bash skills/_shared/telemetry.sh log \
  --project-root="$PWD" --skill=qa \
  --step-num=01 --step-name=collect --status=ok

bash skills/_shared/progress.sh step \
  --project-root="$PWD" --feature-id="$feature_id" \
  --skill=qa --step-num=01 --step-name=collect --status=ok \
  --note="regression=$verdict wireframe_diff=${diff_pct:-skip}"
```

## Acceptance check

- One `.snap/queues/${feature_id}.qa-collect-${run_id}.json` per targeted ticket.
- regression log file exists.
- wireframe block present (even if `enabled=false` so step-02 knows to ignore).

## Next step

→ `step-02-interpret.md`
