---
name: develop
description: Implement tickets — analyze impact, write code, run reviews in parallel (technical+functional+security), apply feedback, commit atomically, push.
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, AskUserQuestion, Task
---

# /develop — ticket → committed code skill

Run after `/ticket` (and optionally `/wireframe`). Picks one ticket (standalone)
or iterates a feature's tickets (session/daemon), implements them, runs three
parallel reviewers, applies aggregated feedback, and produces atomic commits.

## When to use

- A feature has `tickets.json` with at least one `todo`/`in_progress` ticket.
- Working tree is clean (or `--allow-dirty`).
- Repo is a git repository on a branch you can commit to (not directly on a
  protected branch — branch is created idempotently per ticket/feature).

## Pipeline

| # | Step | Purpose |
|---|------|---------|
| 00 | `step-00-init.md`            | Parse args, resolve target (ticket-id or feature_id), load config, pre-flight |
| 01 | `step-01-fetch.md`           | Hydrate ticket(s) from cache → fall back to platform fetch |
| 02 | `step-02-prepare.md`         | Branch idempotent, conventions load (CLAUDE.md, CONTRIBUTING.md), impact_radius |
| 03a | `step-03a-standalone.md`    | One ticket: Phase 1 (analyze/plan/execute/validate) + Phase 2 (3 reviewers parallel + dev fix loop) |
| 03b | `step-03b-loop-session.md`  | Many tickets, same session: foreach ticket → step-03a → atomic commit |
| 03c | `step-03c-loop-daemon.md`   | Generate `daemon.sh` script (no auto-launch) — user runs `bash daemon.sh -n N` |
| 04 | `step-04-sync.md`            | Push branch, open PR (or update existing), patch ticket platform_url + status |
| 05 | `step-05-finish.md`          | Update tickets.json, propose `/qa`, telemetry, terminal |

## Args

```
/develop                              # AskUserQuestion → choose ticket or feature
/develop <ticket-id>                  # standalone (e.g. AUTH-12, #42, t-001)
/develop <feature-id>                 # loop — prompts for --loop=session|daemon
/develop <feature-id> --loop=session  # iterate in same Claude session
/develop <feature-id> --loop=daemon   # generate daemon.sh (manual run)
/develop --resume | -r                # resume via resume-state.sh
/develop --dry-run                    # skip writes (no commit/push, reviewers run on staged diff)
/develop --allow-dirty                # tolerate uncommitted changes pre-run
/develop --retry-fallback=next-ticket|stop  # only with fail_strategy=retry
```

## Configuration (config.develop)

```json
{
  "develop": {
    "review_cycles_max": 3,
    "auto_apply_review_feedback": true,
    "fail_strategy": "next-ticket",
    "reviews": {
      "technical": {"severity_threshold": "minor"},
      "functional": {"severity_threshold": "minor"},
      "security":   {"severity_threshold": "major"}
    }
  }
}
```

- `review_cycles_max` — Phase-2 dev↔reviewer cycles before failing (early stop on
  `critical`).
- `auto_apply_review_feedback` — when false, surfaces feedback for human review
  instead of looping the dev agent.
- `fail_strategy` — what happens when cycles exhausted:
  - `next-ticket` — log severities, skip this ticket, continue (loop modes only).
  - `stop` — dump aggregated_feedback, halt the run.
  - `retry` — re-run Phase 1 once with `retry_strategy_hint`, then fall through
    to `--retry-fallback`.
- Reviewer `severity_threshold` — finding at this level or above blocks the
  cycle from completing.

## Outputs

- One git commit per ticket (`{type}({scope}): {title} ({local_id})`),
  amended on cycle-fix iterations.
- Branch pushed; PR opened (idempotent — re-run updates body, not duplicate).
- `tickets.json` updated: `commit_sha`, `developed_at`, `status="in_review"`.
- `progress.md` step entries for every ticket.

## Resume protocol

`/develop --resume` → `resume-state.sh next --skill=develop`. Resumes either a
single in-progress ticket (Phase 1 or Phase 2) or the next unfinished ticket in
a session loop. Daemon mode is a no-op resume — `daemon.sh` already iterates.

## Acceptance check

- Each targeted ticket has `commit_sha` set + an entry in `progress.md`.
- `git rev-parse --verify <branch>` succeeds.
- For loops: `tickets.json` has `status` advanced for every processed ticket.

## Failure handling

See `step-03a-standalone.md` (cycle / severity / fail_strategy) and
`step-04-sync.md` (push retry, PR conflict).
