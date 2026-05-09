---
name: ticket
description: Decompose a feature PRD into atomic, dev-ready tickets, enrich each with parallel agent research, format per platform, and push to GitHub/GitLab/JIRA via tickets-adapter.
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, AskUserQuestion, Agent
---

# /ticket — feature → tickets skill

Run this skill **after `/define`** when a feature PRD exists and you need to break it
into atomic tickets ready for `/develop`.

## When to use

- A feature PRD (`prd-feature.md`) exists in `.claude/product/features/{feature_id}/`.
- You want a numbered list of dev-ready stories (5-30min, 1-5 files each) on the
  configured ticket platform.
- Resume: `--resume` (`-r`) restarts from the last successful step recorded in the
  feature's `progress.md`.

## Pipeline

| # | Step | Purpose |
|---|------|---------|
| 00 | `step-00-init.md`     | Parse args, resolve `feature_id`, load PRD + config |
| 01 | `step-01-load.md`     | Read `prd-feature.md`, extract AC + scope to context |
| 02 | `step-02-decompose.md`| Break feature into atomic stories (5-30min, 1-5 files) |
| 03 | `step-03-enrich.md`   | Parallel agents: codebase / docs / web search per story |
| 04 | `step-04-format.md`   | Render each story via `templates/ticket-{platform}.md` |
| 05 | `step-05-push.md`     | Push via `tickets-adapter.sh` (MCP > CLI) |
| 06 | `step-06-index.md`    | Cache `tickets.json` + update feature `meta.json` |

## Args

```
/ticket [--resume|-r] [--feature=NN-slug] [--platform=github|gitlab|jira]
        [--max-stories=N] [--dry-run]
```

- `--feature` (required if multiple features defined): target feature_id (partial-match
  via `resume-state.sh`).
- `--platform`: override `config.tickets.platform`.
- `--max-stories`: cap auto-decomposition (default 12).
- `--dry-run`: format + log but skip the platform write (uses tickets-adapter
  `--dry-run`).

## Outputs

- `.claude/product/features/{feature_id}/tickets.json` — cached tickets array (id,
  title, body, labels, status, platform_url).
- `.claude/product/features/{feature_id}/meta.json` — `tickets_count` updated.
- Tickets created on GitHub / GitLab / JIRA (URLs cached above).
- `.claude/product/features/{feature_id}/progress.md` — append-only log.

## Resume protocol

`/ticket --resume --feature=01` delegates to:

```bash
bash skills/_shared/resume-state.sh next --skill=ticket \
  --feature="$feature" --project-root="$PWD"
```

Jump to the returned `next_step` with `feature_id` pre-loaded. See `step-00-init.md`.

## Acceptance check (whole skill)

- Every refined feature in `.claude/product/features/` either has a `tickets.json` with
  ≥ 1 entry, or a `progress.md` ending with `ticket step-NN — fail|skip` and a clear
  reason.
- `tickets.json` schema-validates against `_shared/schemas/tickets.schema.json`.
