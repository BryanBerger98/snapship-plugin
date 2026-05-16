# `/snap:qa` — runtime validation of a developed ticket

Fetches the ticket **live** from the tracker, applies `story_type`-based
filters (Task / Bug skip irrelevant UI checks, Epic is refused), runs the
regression scoped to impacted code (via `code-review-graph`), diffs the
implementation against Frame0 wireframes (Playwright), spawns
`code-reviewer-qa`, cycles dev fixes via `git commit --amend`, and
optionally re-triggers the `/snap:develop` reviewers on the post-QA diff.

## What it does

Validate, after `/snap:develop`, one ticket against acceptance criteria,
regression, wireframe compliance (when applicable), and security /
functional drift introduced after the dev phase.

## Difference with the `/snap:develop` functional review

- Functional review = **static** (reads the code / diff, checks AC textually).
- QA = **runtime** (runs tests, boots the app, compares behaviour to AC
  + wireframes).

## When to use it

- Ticket has `commit_sha` set and `status="in_review"` on the tracker.
- Repo has a resolved `test_command` (or detectable via
  `detect-test-commands.sh`).
- Optional: Frame0 wireframes exist for the UI tickets — enables the
  wireframe diff.

## story_type filters (v1.2)

`/snap:qa` reads `story_type` from the live ticket and gates checks
accordingly:

| story_type   | wireframe_check       | design_check     | regression |
| ------------ | --------------------- | ---------------- | ---------- |
| `user-story` | enabled (per config)  | enabled (per config) | full   |
| `task`       | **skipped**           | **skipped**      | full       |
| `bug`        | **skipped**           | conditional¹     | full       |
| `epic`       | refused — exit 20     |                  |            |

¹ Bug visual: `design_check` is kept when the ticket has a label
`visual` / `ui-bug` **or** has `wireframe_url` set. Otherwise skipped.

Epic refusal is a double-safety check (`/snap:develop` already refuses
Epic at step-01). The error message points at running `/snap:qa
--ticket=<child-id>` on each child instead.

## Syntax

```
/snap:qa --ticket=<platform_id>     # validate one ticket (mandatory in v1.2)
/snap:qa --resume | -r
/snap:qa --dry-run
/snap:qa --no-wireframe-check
/snap:qa --retrigger
/snap:qa --no-doc-update
/snap:qa --keep-runtime
```

`--ticket=` regex per platform:

- `github` / `gitlab` — `^#?[0-9]+$` (e.g. `#42`, `42`)
- `jira` / `linear`   — `^[A-Z][A-Z0-9_]+-[0-9]+$` (e.g. `AUTH-12`, `ENG-99`)

## Flags

| Flag                    | Effect                                                                                  |
| ----------------------- | --------------------------------------------------------------------------------------- |
| `--ticket=<platform_id>`| **Required.** Tracker ID of the ticket to validate.                                     |
| `--resume` / `-r`       | Resume via `progress.sh resume --skill=qa`.                                             |
| `--dry-run`             | Collect-only: no fix loop, no amend.                                                    |
| `--no-wireframe-check`  | Skip the wireframe diff even if the config enables it.                                  |
| `--retrigger`           | Force step-04 even if `config.qa.retrigger_review=false`.                               |
| `--no-doc-update`       | Skip the post-success `/snap:doc-update` auto-trigger.                                  |
| `--keep-runtime`        | Debug only — preserve `.snap/.runtime/<subject-id>/` after exit.                        |

## Pipeline

| #  | Step                    | Role                                                                                   |
| -- | ----------------------- | -------------------------------------------------------------------------------------- |
| 00 | `step-00-init.md`       | Parse args, fetch ticket + parent live, apply `story_type` filters, **spawn `snap-ticket-digest` (consumer=qa)** and cache the condensed brief, scope the diff. |
| 01 | `step-01-collect.md`    | Run regression (scope `impacted` / `full` / `tests-only`) + Playwright wireframe diff (when enabled).  |
| 02 | `step-02-interpret.md`  | Spawn `code-reviewer-qa` (reusing the cached digest) → severity + `qa_feedback_md`, flaky detection. |
| 03 | `step-03-fix.md`        | Cycle: dev agent applies `qa_feedback` → amend commit → re-run step-01.                |
| 04 | `step-04-retrigger.md`  | Opt-in: re-run the 3 `/snap:develop` reviewers on the post-QA diff (1 retrigger max, reuses cached digest). |
| 05 | `step-05-finish.md`     | Ticket status → `qa-validated` (or `blocked`), telemetry, terminal.                    |

## Digest reuse

`step-00-init` issues a single `snap-ticket-digest` subagent call
(`consumer=qa`) and writes the resulting brief to
`.snap/.runtime/<subject-id>/digest.json`. Every downstream reviewer
(`code-reviewer-qa` at step-02, re-triggered `/snap:develop` reviewers
at step-04) **reuses that cached digest** instead of re-reading the raw
ticket payload — single fetch, one digest, multiple consumers.

On digest-parse failure, a `digest_error` warn event is logged and the
skill continues using the raw ticket as a fallback.

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
- `auto_apply_qa_feedback` — when `false`, surface findings to the user
  instead of re-triggering the dev agent.
- `severity_threshold` — a finding at this level or above blocks the
  ticket from reaching `qa-validated`.
- `regression.scope`:
  - `impacted` (default) — only tests transitively reachable from the
    diff via `code-review-graph`'s `get_affected_flows`.
  - `full` — runs the entire `testing.test_command` suite.
  - `tests-only` — fallback when the graph is unavailable: only
    `*.test.*` / `*.spec.*` files transitively imported from changed
    files.
- `wireframe_check.diff_threshold_pct` — structural diff tolerance against
  the Frame0 PNGs; above this → finding.

## Outputs

Remote (single source of truth):

- Ticket patched on the tracker with `status="qa-validated"` and
  `qa_validated_at` timestamp via `tickets-adapter.sh patch-ticket`.
- Ticket body amended with the QA verdict (per-platform template).
- Optional: re-review summary appended (when the retrigger ran).

Local (runtime — gitignored, purged at end of skill):

- `.snap/.runtime/<subject-id>/ticket.json` — live ticket snapshot.
- `.snap/.runtime/<subject-id>/digest.json` — cached ticket digest.
- `.snap/.runtime/<subject-id>/files.txt` — diff scope for regression + reviewers.
- `.snap/progress.json` — in-flight skill state.
- `.snap/telemetry.ndjson` — append-only event log.

v1.2 makes no local `.snap/tickets/` writes — the tracker is the single
source of truth (no local tickets cache anywhere in the QA flow).

## Resume protocol

```bash
/snap:qa --resume --ticket=<platform_id>
```

Same partial-match contract as the other skills via
`progress.sh resume --skill=qa`.

## Examples

```bash
# Standard QA flow.
/snap:qa --ticket=AUTH-12

# Collect-only (no fix loop, no amend).
/snap:qa --ticket=AUTH-12 --dry-run

# Skip wireframe check (config says yes but you want to bypass).
/snap:qa --ticket=AUTH-12 --no-wireframe-check

# Force the post-QA reviewer retrigger.
/snap:qa --ticket=AUTH-12 --retrigger

# Resume after a crash.
/snap:qa --resume --ticket=AUTH-12
```

## Next step

`/snap:doc-update --ticket=<platform_id>` (auto-triggered when
`documentation.auto_update_on_qa_success: true`) to refresh the journey
pages impacted by this ticket.
