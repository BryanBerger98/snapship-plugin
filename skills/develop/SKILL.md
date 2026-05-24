---
name: develop
description: Implement one tracker ticket — fetch live, refuse Epic, resolve worktree per story_type, run snap-developer + 3 parallel reviewers (technical/functional/security), commit atomically, push, sync remote. Post-merge sub-flow auto-closes parent Epic when all its children are done (capability-gated).
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, AskUserQuestion, Agent
---

# /snap:develop — ticket → committed code skill

Run after `/snap:ticket` produced and pushed a ticket. Reads the ticket **live**
from the tracker (no PRD lookup, no `.snap/stories/` read), implements it, runs
three parallel reviewers, applies aggregated feedback, and produces an atomic
commit + PR. A separate post-merge entry-point auto-closes the parent Epic
when all its children are done.

## Prerequisites

- `/snap:init` ran and `tickets.platform != "none"` in `snap.config.json`.
- The ticket exists on the tracker with a resolved `platform_id` and a
  `story_type` ∈ `{user-story, task, bug}`. Epic is **refused**
  (exit code 20).
- Working tree clean (or `--allow-dirty`).
- Git repo on a branch you can commit to (protected branches refused).

## Pipeline

| #   | Step                       | Purpose |
|-----|----------------------------|---------|
| 00  | `step-00-init.md`          | Parse args, validate `--ticket=<platform_id>`, init ephemeral subject, pre-fetch ticket + parent live |
| 01  | `step-01-fetch.md`         | Read ticket from cache, **filter `story_type=epic`**, extract external refs (wireframe/design/doc) |
| 02  | `step-02-prepare.md`       | Worktree resolve per `story_type` (dedicated or reuse), branch checkout, conventions + impact radius |
| 03a | `step-03a-standalone.md`   | Phase 1 (analyze/plan/execute/validate) + Phase 2 (3 reviewers parallel + dev fix loop) + atomic commit |
| 04  | `step-04-sync.md`          | Push branch, open/update PR, patch ticket `in_review` remote, post review thread (best-effort) |
| 05  | `step-05-finish.md`        | Print summary, hand off to `/qa`, mandatory ephemeral purge |
| 99  | `step-99-post-merge.md`    | **Out-of-band** — auto-close parent Epic when all children done (capability-gated, opt-out via `--no-epic-close`) |

## Args

```
/snap:develop --ticket=<platform_id>
              [--dry-run] [--allow-dirty]
              [--no-epic-close] [--keep-runtime]
              [--resume|-r] [--retry-fallback=next-ticket|stop]
              [--post-merge]
```

- `--ticket=<platform_id>` — **required**. Format validated per platform :
  - github / gitlab : `#42` or `42`
  - jira / linear   : `AUTH-12`, `ENG-42`
- `--dry-run` — reviewers run on staged diff ; no commit, no push.
- `--allow-dirty` — tolerate uncommitted changes pre-run.
- `--no-epic-close` — opt-out from post-merge Epic auto-close.
- `--keep-runtime` — **debug only** : preserve the ephemeral subject for inspection.
- `--resume` / `-r` — short-circuit via `progress.sh resume`.
- `--retry-fallback=next-ticket|stop` — only with `fail_strategy=retry`.
- `--post-merge` — jump directly to `step-99-post-merge.md` (skip 00→05).

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

- `review_cycles_max` — Phase 2 dev↔reviewer cycles before failing (early stop
  on `critical`).
- `auto_apply_review_feedback` — when `false`, surfaces feedback for human
  review instead of looping the dev agent.
- `fail_strategy` — what happens when cycles exhausted :
  - `next-ticket` — log severities, skip the ticket (status=`blocked` remote).
  - `stop` — dump `aggregated_feedback`, halt.
  - `retry` — re-run Phase 1 once with `retry_strategy_hint`, then fall through
    to `--retry-fallback`.
- Reviewer `severity_threshold` — each reviewer (technical/functional/security)
  blocks the cycle on **its own** threshold: a finding at that level or above
  (ordering `none < info < minor < major < critical`) blocks completion. The
  comparison lives in `skills/_shared/severity-gate.sh`.

## Outputs

Remote (single source of truth) :

- One git commit per ticket (`{commit_type}({scope}): {title} ({platform_id})`)
  pushed to the resolved branch.
- PR opened/updated on the tracker platform (idempotent).
- Ticket status → `in_review` (best-effort) ; commit SHA referenced on the
  ticket via a comment.

Local (runtime — gitignored, purged at end of skill) :

- `.snap/.runtime/<subject-id>/ticket.json` — live ticket snapshot.
- `.snap/.runtime/<subject-id>/parent.json` — parent ticket (when present).
- `.snap/.runtime/<subject-id>/refs.json` — extracted external URLs.
- `.snap/.runtime/<subject-id>/worktree.json` — resolved branch + path.
- `.snap/.runtime/<subject-id>/commit.json` — commit SHA + timestamp.
- `.snap/progress.json` — in-flight skill state, purged on terminal-step ok.
- `.snap/telemetry.ndjson` — append-only event log.

`/develop` **does not** read or write `.snap/tickets/{story_id}.json` — that
file belongs to `/snap:ticket`. v1.2 is fully PRD-agnostique.

## Epic filter (exit 20)

`story_type=epic` is refused with exit code `20` and an explicit message :

```
ERROR (exit=20): ticket <id> has story_type=epic.
Epic n'est pas une unité de livraison — decompose en User Stories
(/snap:ticket --feature=<story_id>) puis relance /develop sur une US.
```

Wrappers (`/qa`, CI gates) can branch on this exit code.

## Worktree strategy (decision #11, via `worktree-helper.sh`)

| Ticket `story_type`            | Strategy   | Branch                  |
|--------------------------------|------------|-------------------------|
| `user-story`                   | dedicated  | new                     |
| `bug`                          | dedicated  | new                     |
| `task` (parent = `user-story`) | **reuse**  | parent US branch        |
| `task` (parent = `bug`, `epic`, none) | dedicated | new              |
| `epic`                         | **refused** (step-01 filter) | — |

`reuse` requires the parent US branch to exist locally — if missing, step-02
fails clean with the parent ref so the user can develop the US first.

## Post-merge Epic auto-close

Triggered out-of-band after a PR merge :

```bash
/snap:develop --post-merge --ticket=<platform_id>
```

Capability matrix (static defaults) :

| Platform | `supports_epic_auto_close` | Behaviour                              |
|----------|---------------------------:|----------------------------------------|
| github   | `false`                    | skip silently (no API close on parents) |
| gitlab   | `true`                     | Epic close API                          |
| jira     | `true`                     | transition workflow → `Done`            |
| linear   | `true`                     | state → `Completed`                     |

Opt-out : `--no-epic-close`. CI hooks can also pre-set
`NO_EPIC_CLOSE=true` in the environment.

## Resume protocol

`/snap:develop --resume --ticket=<id>` → `progress.sh resume --skill=develop`.
Resumes at the last in-flight step recorded for that ticket. `--keep-runtime`
on the initial run keeps `.snap/.runtime/<subject>/` so resume can pick up
without re-fetching.

## Examples

```bash
# Standard flow — implement ticket #42 on GitHub.
/snap:develop --ticket=#42

# Same on Jira.
/snap:develop --ticket=AUTH-12

# Dry-run for review on a staged diff.
/snap:develop --ticket=AUTH-12 --dry-run

# Resume after a crash.
/snap:develop --resume --ticket=AUTH-12

# Debug : keep the ephemeral subject for inspection.
/snap:develop --ticket=AUTH-12 --keep-runtime

# Post-merge : close parent Epic if all siblings done.
/snap:develop --post-merge --ticket=AUTH-12

# Same, opt-out of Epic auto-close.
/snap:develop --post-merge --ticket=AUTH-12 --no-epic-close
```

## Acceptance check (whole skill)

- Ticket has remote status `in_review` and a `commit_sha` referenced via
  comment.
- PR exists on the tracker for the resolved branch.
- `.snap/.runtime/<subject-id>/` purged (unless `--keep-runtime`).
- `progress.json.in_flight` no longer contains a `develop` entry for the
  ticket.

## Failure handling

- `step-01` Epic-refusé → exit 20 (dedicated).
- `step-02` worktree reuse but parent branch missing → fail clean naming the
  parent ticket.
- `step-03a` cycles exhausted → governed by `fail_strategy` (next-ticket /
  stop / retry).
- `step-04` push / PR fail → idempotent retry on `--resume`.
- `step-99` capability missing → skip silently (no failure).
