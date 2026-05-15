---
name: qa
description: Validate developed tickets — run regression (scope=impacted via code-review-graph), wireframe diff (Playwright vs Frame0), spawn code-reviewer-qa, cycle dev fixes via amend, optional retrigger of /develop reviewers.
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, AskUserQuestion, Task
---

# /qa — validate developed tickets skill

Run after `/develop` produced a commit (or several). Validates against AC,
regression, wireframe match, and security/functional drift introduced after
the dev phase.

## When to use

- A ticket has `commit_sha` set and `status="in_review"` in tickets.json.
- The repo has a `test_command` resolved (or detectable via
  `detect-test-commands.sh`).
- Optionally: Frame0 wireframes exist for UI tickets — enables wireframe diff.

## Pipeline

| # | Step | Purpose |
|---|------|---------|
| 00 | `step-00-init.md`       | Parse args, resolve target ticket(s), load config, scope diff |
| 01 | `step-01-collect.md`    | Run regression (scope=impacted/full/tests-only) + Playwright wireframe diff |
| 02 | `step-02-interpret.md`  | Spawn `code-reviewer-qa` agent → severity + qa_feedback_md, flaky detection |
| 03 | `step-03-fix.md`        | Cycle: developer agent applies qa_feedback → amend commit → re-run step-01 |
| 04 | `step-04-retrigger.md`  | Opt-in: re-run /develop's 3 reviewers on the post-QA diff (1 retrigger max) |
| 05 | `step-05-finish.md`     | Update ticket status → `qa-validated` (or `blocked`), telemetry, terminal |

## Args

```
/qa                            # AskUserQuestion: which ticket / feature?
/qa <ticket-id>                # validate one ticket
/qa <feature-id>               # validate every in_review ticket in feature
/qa --resume | -r              # resume via progress.sh resume
/qa --dry-run                  # collect-only; no fix loop, no amend
/qa --no-wireframe-check       # skip wireframe diff even if config enables it
/qa --retrigger                # force step-04 even if config.retrigger_review=false
```

## Configuration (config.qa)

```json
{
  "qa": {
    "qa_cycles_max": 2,
    "auto_apply_qa_feedback": true,
    "severity_threshold": "minor",
    "retrigger_review": false,
    "regression": {"enabled": true, "scope": "impacted"},
    "wireframe_check": {"enabled": false, "mode": "playwright", "diff_threshold_pct": 5}
  }
}
```

- `qa_cycles_max` — dev↔qa fix cycles before failing.
- `auto_apply_qa_feedback` — when false, surface findings to user instead of
  looping the developer agent.
- `severity_threshold` — finding at this level or above blocks the ticket from
  reaching `qa-validated`.
- `regression.scope`:
  - `impacted` (default) — only tests transitively reachable from the diff via
    code-review-graph `get_affected_flows`.
  - `full` — run `testing.test_command` whole suite.
  - `tests-only` — fallback when graph unavailable: run only `*.test.*` /
    `*.spec.*` files transitively imported from changed files.
- `wireframe_check.diff_threshold_pct` — structural-diff tolerance against
  Frame0 PNGs; above threshold → finding with severity from
  `severity_on_mismatch`.

## Outputs

- Each validated ticket: `status="qa-validated"`, `qa_validated_at` set in
  `.snap/tickets/${feature_id}.json`.
- Feature manifest state advanced to `qa-validated` when all targeted tickets
  pass.
- Ticket platform body amended with QA verdict (per-platform template).
- `progress.json` step entries.
- Optional: re-review summary appended (when retrigger ran).

## Resume protocol

`/qa --resume` → `progress.sh resume --skill=qa`. Same partial-match contract
as the other skills.

## Acceptance check

- Each targeted ticket either reaches `qa-validated` or is left as `blocked`
  with a finding-summary in progress.json.
- Regression command exit 0 (or every flaky retry settled).
- Wireframe diff (if enabled) below threshold.

## Failure handling

See `step-03-fix.md` (cycle exhaustion) and `step-04-retrigger.md` (one-shot
re-review semantics).
