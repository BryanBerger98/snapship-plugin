# `/snap:qa` — runtime validation of developed tickets

Validates developed tickets: regression (scope = impacted via
code-review-graph), wireframe diff (Playwright vs Frame0), spawns a
`code-reviewer-qa` agent, runs a dev fix loop via amend, and optionally
retriggers the `/snap:develop` reviewers.

## What it does

Validate, after `/snap:develop`, one or more commits against acceptance
criteria, regression, wireframe compliance, and security / functional
drifts introduced after the dev phase.

## When to use it

- A ticket has a `commit_sha` and `status="in_review"` in `tickets.json`.
- The repo has a resolved `test_command` (or one detectable via
  `detect-test-commands.sh`).
- Optional: Frame0 wireframes exist for the UI tickets → enables the
  wireframe diff.

## Difference with the `/snap:develop` functional review

- Functional review = **static** (reads the code / diff, checks the AC
  textually).
- QA = **runtime** (runs the tests, boots the app, compares behavior to
  AC + wireframes).

## Syntax

```
/snap:qa                            # AskUserQuestion: which ticket / feature?
/snap:qa <ticket-id>                # validates one ticket
/snap:qa <feature-id>               # validates every in_review ticket of the feature
/snap:qa --resume | -r
/snap:qa --dry-run
/snap:qa --no-wireframe-check
/snap:qa --retrigger
```

## Flags

| Flag                    | Effect                                                                               |
| ----------------------- | ------------------------------------------------------------------------------------ |
| `<ticket-id>`           | Validates a single ticket.                                                           |
| `<feature-id>`          | Validates every `in_review` ticket of the feature.                                   |
| `--resume` / `-r`       | Resumes via `progress.sh resume next --skill=qa`.                                    |
| `--dry-run`             | Collect only: no fix loop, no amend.                                                 |
| `--no-wireframe-check`  | Skips the wireframe diff even if the config enables it.                              |
| `--retrigger`           | Forces step-04 even if `config.qa.retrigger_review=false`.                           |

## Pipeline

| #  | Step                    | Role                                                                              |
| -- | ----------------------- | --------------------------------------------------------------------------------- |
| 00 | `step-00-init.md`       | Parses args, resolves the target ticket(s), loads config, scopes the diff.        |
| 01 | `step-01-collect.md`    | Runs the regression (scope impacted / full / tests-only) + Playwright wireframe diff. |
| 02 | `step-02-interpret.md`  | Spawns the `code-reviewer-qa` agent → severity + `qa_feedback_md`, flaky detection. |
| 03 | `step-03-fix.md`        | Cycle: the dev agent applies `qa_feedback` → amends the commit → re-runs step-01.  |
| 04 | `step-04-retrigger.md`  | Opt-in: re-runs the 3 `/snap:develop` reviewers on the post-QA diff (1 retrigger max). |
| 05 | `step-05-finish.md`     | Ticket status → `qa-validated` (or `blocked`), telemetry, terminal.               |

## Configuration (`config.qa`)

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

- `qa_cycles_max` — dev fix ↔ QA cycles before failing.
- `auto_apply_qa_feedback` — if `false`, findings are presented to the
  user instead of re-triggering the dev agent.
- `severity_threshold` — a finding at this level or above prevents the
  ticket from reaching `qa-validated`.
- `regression.scope`:
  - `impacted` (default) — only tests transitively reachable from the
    diff via `get_affected_flows` (code-review-graph).
  - `full` — runs the entire `testing.test_command` suite.
  - `tests-only` — fallback when the graph is unavailable: only the
    `*.test.*` / `*.spec.*` files transitively imported from changed
    files.
- `wireframe_check.diff_threshold_pct` — structural diff tolerance against
  the Frame0 PNGs; above this → finding.

## Outputs

- Each validated ticket: `status="qa-validated"`, `qa_validated_at` set.
- Platform ticket body amended with the QA verdict (per-platform template).
- Step entries in `progress.json`.
- Optional: re-review summary appended (if the retrigger ran).

## Next step

`/snap:doc-update --feature=NN-slug` to refresh the living functional
docs (auto-triggered if `documentation.auto_update_on_qa_success: true`).
