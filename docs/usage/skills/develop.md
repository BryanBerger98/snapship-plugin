# `/snap:develop` — ticket → committed code

Implements tickets: analyzes impact, writes code, runs three reviewers
in parallel (technical + functional + security), applies the aggregated
feedback, then produces atomic commits and pushes the branch.

## What it does

Take a ticket (standalone mode) or iterate over a feature's tickets
(session / daemon loop mode), implement them, drive the reviewers to
convergence, and ship one atomic commit per ticket.

## When to use it

- A feature has a `tickets.json` with at least one `todo` /
  `in_progress` ticket.
- The working tree is clean (or `--allow-dirty`).
- The repo is a git repo on a committable branch (not directly on a
  protected branch — the branch is created idempotently per ticket / feature).

## Syntax

```
/snap:develop                              # AskUserQuestion → pick ticket or feature
/snap:develop <ticket-id>                  # standalone (e.g. AUTH-12, #42, t-001)
/snap:develop <feature-id>                 # loop — asks for --loop=session|daemon
/snap:develop <feature-id> --loop=session  # iterates in the same Claude session
/snap:develop <feature-id> --loop=daemon   # generates daemon.sh (manual launch)
/snap:develop --resume | -r
/snap:develop --dry-run
/snap:develop --allow-dirty
/snap:develop --retry-fallback=next-ticket|stop
```

## Flags

| Flag                                       | Effect                                                                                 |
| ------------------------------------------ | -------------------------------------------------------------------------------------- |
| `<ticket-id>`                              | Standalone mode: a single ticket.                                                      |
| `<feature-id>`                             | Loop mode: iterates over the feature's tickets (asks for the mode if not specified).   |
| `--loop=session`                           | Iterates over tickets in the same Claude session.                                      |
| `--loop=daemon`                            | Generates `daemon.sh` (never auto-launched — the user runs `bash daemon.sh -n N`).    |
| `--resume` / `-r`                          | Resumes via `progress.sh resume next --skill=develop`.                                 |
| `--dry-run`                                | No writes: no commit, no push; reviewers run on the staged diff.                       |
| `--allow-dirty`                            | Tolerates uncommitted changes before the run.                                          |
| `--retry-fallback=next-ticket\|stop`       | Fallback behavior, only with `fail_strategy=retry`.                                    |

## Pipeline

| #   | Step                       | Role                                                                                  |
| --- | -------------------------- | ------------------------------------------------------------------------------------- |
| 00  | `step-00-init.md`          | Parses args, resolves the target (ticket-id or feature-id), loads config, preflight.  |
| 01  | `step-01-fetch.md`         | Hydrates ticket(s) from cache → fallback to platform fetch.                           |
| 02  | `step-02-prepare.md`       | Idempotent branch, loads conventions (CLAUDE.md, CONTRIBUTING.md), impact radius.     |
| 03a | `step-03a-standalone.md`   | Single ticket: Phase 1 (analyze / plan / execute / validate) + Phase 2 (3 reviewers in parallel + dev fix loop). |
| 03b | `step-03b-loop-session.md` | Multiple tickets, same session: foreach ticket → step-03a → atomic commit.            |
| 03c | `step-03c-loop-daemon.md`  | Generates `daemon.sh` (no auto-launch) — the user runs `bash daemon.sh -n N`.         |
| 04  | `step-04-sync.md`          | Pushes the branch, opens the PR (or updates the existing one) via the resolved template (config override > `.github`/`.gitlab` PR template > bundled), patches `platform_url` + ticket status. |
| 05  | `step-05-finish.md`        | Updates `tickets.json`, suggests `/snap:qa`, telemetry, terminal.                     |

## Configuration (`config.develop`)

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

- `review_cycles_max` — number of dev ↔ reviewer cycles in Phase 2 before
  failing (early stop on `critical`).
- `auto_apply_review_feedback` — if `false`, feedback is presented for
  human review instead of re-triggering the dev agent.
- `fail_strategy` — behavior when cycles are exhausted:
  - `next-ticket` — logs severities, skips this ticket, continues (loop modes only).
  - `stop` — dumps `aggregated_feedback`, stops the run.
  - `retry` — re-runs Phase 1 once with `retry_strategy_hint`, then falls
    back to `--retry-fallback`.
- `reviews.{type}.severity_threshold` — a finding at this level or above
  blocks the end of the cycle. Scale: `info` < `minor` < `major` < `critical`.

## Outputs

- One git commit per ticket (`{type}({scope}): {title} ({local_id})`), amended on
  fix iterations.
- Branch pushed; PR opened (idempotent — a re-run updates the body, does
  not duplicate).
- `tickets.json` updated: `commit_sha`, `developed_at`, `status="in_review"`.
- Step entries in `progress.json` for each ticket.

## Next step

`/snap:qa <ticket-id>` (standalone) or `/snap:qa <feature-id>` (loop) for
runtime validation.
