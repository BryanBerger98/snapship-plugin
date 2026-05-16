---
name: qa
description: Validate one developed ticket — fetch ticket live (tracker = source), apply story_type filters (task/bug skip UI checks, Epic refused), run regression (scope=impacted via code-review-graph), wireframe diff (Playwright vs Frame0), spawn code-reviewer-qa, cycle dev fixes via amend, optional retrigger of /develop reviewers.
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, AskUserQuestion, Task
---

# /qa — validate developed ticket skill (v1.2)

Run after `/develop` produced a commit. Validates against AC, regression,
wireframe match (when applicable per `story_type`), and security/functional
drift introduced after the dev phase.

## When to use

- Ticket has `commit_sha` set and `status="in_review"` on the tracker.
- Repo has a `test_command` resolved (or detectable via
  `detect-test-commands.sh`).
- Optionally: Frame0 wireframes exist for UI tickets — enables wireframe diff.

## story_type filters (v1.2)

`/qa` applies filters before running checks — checks are gated by `story_type` :

| story_type | wireframe_check | design_check | regression |
|------------|-----------------|--------------|------------|
| `user-story` | enabled (config) | enabled (config) | full |
| `task` | skipped | skipped | full |
| `bug` | skipped | conditional¹ | full |
| `epic` | refused — exit 20 |||

¹ Bug visual : `design_check` kept when ticket has label `visual` / `ui-bug`
OR `wireframe_url` set. Otherwise skipped.

Epic refusal is a double-safety check (`/develop` already refuses Epic at
step-01). Hint emitted : run `/qa --ticket=<child-id>` on each child instead.

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
/qa --ticket=<platform_id>     # validate one ticket (mandatory in v1.2)
/qa --resume | -r              # resume via progress.sh resume
/qa --dry-run                  # collect-only; no fix loop, no amend
/qa --no-wireframe-check       # skip wireframe diff even if config enables it
/qa --retrigger                # force step-04 even if config.retrigger_review=false
/qa --no-doc-update            # skip post-success /snap:doc-update auto-trigger
/qa --keep-runtime             # preserve .snap/.runtime/<subject-id>/ on exit
```

`--ticket=` regex per platform:
- `github|gitlab` : `^#?[0-9]+$` (e.g. `#42`, `42`)
- `jira|linear`   : `^[A-Z][A-Z0-9_]+-[0-9]+$` (e.g. `AUTH-12`, `ENG-99`)

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

- Validated ticket: tracker patched with `status="qa-validated"`,
  `qa_validated_at` timestamp set via `tickets-adapter.sh patch-ticket`.
- Ticket platform body amended with QA verdict (per-platform template).
- `progress.json` step entries.
- Optional: re-review summary appended (when retrigger ran).

v1.2: no local `.snap/tickets/` writes — tracker is the single source of
truth (decision 3). Ephemeral `.snap/.runtime/<subject-id>/` is purged on
exit unless `--keep-runtime` is set.

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
