# `/snap:develop` — tracker ticket → committed code

Implements one tracker ticket. Fetches the payload live, refuses Epic,
resolves the worktree by `story_type`, runs `snap-developer` plus three
parallel reviewers (technical / functional / security), produces an atomic
commit, opens / updates the PR, and — out-of-band post-merge — auto-closes
the parent Epic when all its children are done (capability-gated).

## What it does

Read a ticket **live from the tracker** (no PRD lookup, no local
`.snap/stories/` read), implement it, drive the reviewers to convergence,
and ship one atomic commit per ticket.

v1.2 is fully **remote-first** and **PRD-agnostic**: `/snap:develop`
never reads `.snap/manifests/{story_id}/`, `.snap/stories/`, or
`.snap/tickets/`. The tracker is the single source of truth and the
ticket carries every reference (wireframe / design / doc URLs) needed
to implement.

## When to use it

- A ticket exists on the tracker with a resolved `platform_id` and
  `story_type ∈ {user-story, task, bug}`. Epic is **refused** (exit 20).
- Working tree is clean (or `--allow-dirty`).
- Git repo on a committable branch (protected branches refused — the
  branch is created idempotently per ticket).

## Prerequisites

- `/snap:init` ran and `tickets.platform != "none"`.
- The ticket was created by `/snap:ticket` (or manually on the tracker;
  `/develop` runs on external tickets too, with minimal context derived
  from the live payload).

## Syntax

```
/snap:develop --ticket=<platform_id>
              [--dry-run] [--allow-dirty]
              [--no-epic-close] [--keep-runtime]
              [--resume|-r] [--retry-fallback=next-ticket|stop]
              [--post-merge]
```

`--ticket=<platform_id>` is **mandatory**. v1.2 dropped the old
`--feature-id=<local_id>` form — there is no local fallback.

Platform ID regex:

- `github` / `gitlab` — `#42` or `42`
- `jira` / `linear`   — `AUTH-12`, `ENG-99`

## Flags

| Flag                                       | Effect                                                                                          |
| ------------------------------------------ | ----------------------------------------------------------------------------------------------- |
| `--ticket=<platform_id>`                   | **Required.** Tracker ID of the ticket to implement.                                            |
| `--dry-run`                                | Reviewers run on the staged diff; no commit, no push.                                           |
| `--allow-dirty`                            | Tolerate uncommitted changes before the run.                                                    |
| `--no-epic-close`                          | Opt-out from post-merge Epic auto-close (step-99).                                              |
| `--keep-runtime`                           | Debug only — preserve `.snap/.runtime/<subject-id>/` after the run.                             |
| `--resume` / `-r`                          | Short-circuit via `progress.sh resume --skill=develop`.                                         |
| `--retry-fallback=next-ticket\|stop`       | Only with `fail_strategy=retry`.                                                                |
| `--post-merge`                             | Jump directly to `step-99-post-merge` (skip 00 → 05).                                           |

## Pipeline

| #   | Step                       | Role                                                                                       |
| --- | -------------------------- | ------------------------------------------------------------------------------------------ |
| 00  | `step-00-init.md`          | Parse args, validate `--ticket=<platform_id>`, init ephemeral subject, **pre-fetch ticket + parent live** via `tickets-adapter.sh`. |
| 01  | `step-01-fetch.md`         | Read ticket from cache, **filter `story_type=epic`** (exit 20), extract external refs (wireframe / design / doc). |
| 02  | `step-02-prepare.md`       | Worktree resolve per `story_type` (dedicated or reuse), branch checkout, conventions + impact radius. |
| 03a | `step-03a-standalone.md`   | Phase 1 (analyze / plan / execute / validate) + Phase 2 (3 reviewers in parallel + dev fix loop) + atomic commit. |
| 04  | `step-04-sync.md`          | Push branch, open / update PR, patch ticket `in_review` remote, post review thread (best-effort). |
| 05  | `step-05-finish.md`        | Print summary, hand off to `/snap:qa`, **mandatory ephemeral purge**.                       |
| 99  | `step-99-post-merge.md`    | Out-of-band — auto-close parent Epic when all children are done (capability-gated, opt-out via `--no-epic-close`). |

## Epic filter (exit 20)

`story_type=epic` is rejected at step-01 with a dedicated exit code so
wrappers (`/snap:qa`, CI gates) can branch on it:

```
ERROR (exit=20): ticket <id> has story_type=epic.
Epic n'est pas une unité de livraison — decompose en User Stories
(/snap:ticket --story-id=<story_id>) puis relance /develop sur une US.
```

## Worktree strategy (by `story_type`)

| Ticket `story_type`                          | Strategy   | Branch                       |
| -------------------------------------------- | ---------- | ---------------------------- |
| `user-story`                                 | dedicated  | new                          |
| `bug`                                        | dedicated  | new                          |
| `task` — parent = `user-story`               | **reuse**  | parent US branch (checkout)  |
| `task` — parent = `epic`, `bug`, or standalone | dedicated | new                         |
| `epic`                                       | **refused** at step-01       | —                            |

`reuse` requires the parent US branch to exist locally. When missing,
step-02 fails clean naming the parent ticket so the user can develop the
parent US first.

## Post-merge Epic auto-close

Triggered out-of-band after the PR for a ticket merges:

```bash
/snap:develop --post-merge --ticket=<platform_id>
```

`step-99-post-merge` checks the parent Epic (if any), then asks the
tracker adapter to close it when all children are `done`. The adapter
declares the capability statically:

| Platform | `supports_epic_auto_close` | Behaviour                                       |
| -------- | -------------------------: | ----------------------------------------------- |
| github   | `false`                    | Skip silently (no API close on parent issues).  |
| gitlab   | `true`                     | Epic close API.                                 |
| jira     | `true`                     | Transition workflow → `Done`.                   |
| linear   | `true`                     | State → `Completed`.                            |

Opt-out:

- Per-run: `--no-epic-close`.
- Environment: `NO_EPIC_CLOSE=true` (handy in CI hooks).

The auto-close action is logged in `progress.json` and telemetry.

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

- `review_cycles_max` — Phase 2 dev ↔ reviewer cycles before failing
  (early stop on `critical`).
- `auto_apply_review_feedback` — when `false`, feedback is surfaced for
  human review instead of looping the dev agent.
- `fail_strategy` — behaviour when cycles are exhausted:
  - `next-ticket` — log severities, skip the ticket (`status=blocked` remote).
  - `stop` — dump `aggregated_feedback`, halt.
  - `retry` — re-run Phase 1 once with `retry_strategy_hint`, then fall
    through to `--retry-fallback`.
- `reviews.{type}.severity_threshold` — a finding at this level or
  above blocks the cycle from completing. Scale:
  `info < minor < major < critical`.

## Outputs

Remote (single source of truth):

- One git commit per ticket
  (`{commit_type}({scope}): {title} ({platform_id})`).
- PR opened / updated on the tracker platform (idempotent).
- Ticket status → `in_review` (best-effort); commit SHA referenced on
  the ticket via a comment.
- Post-merge: parent Epic closed when capability + all-children-done
  are satisfied.

Local (runtime — gitignored, purged at end of skill):

- `.snap/.runtime/<subject-id>/ticket.json` — live ticket snapshot.
- `.snap/.runtime/<subject-id>/parent.json` — parent ticket (when present).
- `.snap/.runtime/<subject-id>/refs.json` — extracted external URLs.
- `.snap/.runtime/<subject-id>/worktree.json` — resolved branch + path.
- `.snap/.runtime/<subject-id>/commit.json` — commit SHA + timestamp.
- `.snap/progress.json` — in-flight skill state.
- `.snap/telemetry.ndjson` — append-only event log.

`/snap:develop` does **not** read or write `.snap/tickets/` or
`.snap/manifests/` — those belong to `/snap:ticket` and `/snap:define`.

## Resume protocol

```bash
/snap:develop --resume --ticket=<platform_id>
```

Resumes at the last in-flight step recorded for that ticket. Pair with
`--keep-runtime` on the initial run to skip re-fetching the ticket
payload.

## Examples

```bash
# Standard flow — implement ticket #42 on GitHub.
/snap:develop --ticket=#42

# Same on Jira.
/snap:develop --ticket=AUTH-12

# Dry-run — reviewers run on the staged diff, no commit.
/snap:develop --ticket=AUTH-12 --dry-run

# Resume after a crash.
/snap:develop --resume --ticket=AUTH-12

# Debug — keep the ephemeral subject for inspection.
/snap:develop --ticket=AUTH-12 --keep-runtime

# Post-merge — close parent Epic if all siblings are done.
/snap:develop --post-merge --ticket=AUTH-12

# Same — opt-out of Epic auto-close.
/snap:develop --post-merge --ticket=AUTH-12 --no-epic-close
```

## Next step

`/snap:qa --ticket=<platform_id>` for runtime validation.
