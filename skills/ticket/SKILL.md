---
name: ticket
description: Decompose a feature PRD into atomic, dev-ready tickets, enrich each with parallel agent research, format per platform, and push to GitHub/GitLab/JIRA/Linear via tickets-adapter. Blocks when tickets.platform = "none".
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, AskUserQuestion, Agent
---

# /snap:ticket — feature → tickets skill

Run this skill **after `/snap:define`** when a feature manifest exists and you
need to break the PRD into atomic tickets ready for `/snap:develop`.

## Prerequisite

- `/snap:init` ran and `tickets.platform != "none"` in `snap.config.json`.
  If `none`, this skill **blocks** with:

  ```
  ERROR: tickets.platform is "none" — no tracker configured.
  Re-run /snap:init --force to set a tracker, then retry /snap:ticket.
  ```
  (v1.0 decision : `/snap:ticket` is mandatory in the pipeline, hard-block
  is honest about the gap.)

- `/snap:define` produced the feature manifest at
  `.snap/manifests/{story_id}.manifest.json` with `refs.prd.sync_status =
  "synced"`. The PRD body is fetched from remote in step-01 if the local
  staging file is missing.

## When to use

- A manifest exists for the feature and you want a numbered list of dev-ready
  stories (5-30 min, 1-5 files each) on the configured tracker.
- Resume : `--resume` (`-r`) restarts from the last in-flight step recorded in
  `.snap/progress.json`.

## Pipeline

| # | Step | Purpose |
|---|------|---------|
| 00 | `step-00-init.md`     | Parse args, resolve `story_id`, load config, block if `tickets.platform=none` |
| 01 | `step-01-load.md`     | Ensure PRD staging present (fetch from remote if needed), extract AC + scope to context |
| 02 | `step-02-decompose.md`| Break feature into atomic stories (5-30 min, 1-5 files) |
| 03 | `step-03-enrich.md`   | Parallel agents : codebase / docs / web search per story |
| 04 | `step-04-format.md`   | Render each story via `templates/ticket-{platform}.md` (per type + platform) |
| 05 | `step-05-push.md`     | Push via `tickets-adapter.sh` (CLI > MCP fallback) |
| 06 | `step-06-index.md`    | Promote draft → `.snap/tickets/{fid}.json`, ack refs into manifest |

## Args

```
/snap:ticket [--resume|-r] [--feature=NN-slug]
             [--platform=github|gitlab|jira|linear]
             [--max-stories=N] [--dry-run]
```

- `--feature` (required if multiple manifests): target `story_id`
  (partial-match supported).
- `--platform`: override `config.tickets.platform`.
- `--max-stories`: cap auto-decomposition (default 12).
- `--dry-run`: format + log but skip the platform write.

## Outputs

Local (persistent — references to remote) :

- `.snap/tickets/{story_id}.json` — cached tickets array (local_id,
  platform_id, url, title, status, …) — schema `tickets.schema.json`.
- `.snap/manifests/{story_id}.manifest.json` — `refs.tickets` populated by
  `sync-push.sh ack` (platform, url, synced_at, sync_status).

Remote (single source of truth) :

- Tickets / issues on GitHub / GitLab / JIRA / Linear (URLs cached above).

Local (runtime — gitignored) :

- `.snap/progress.json` — in-flight skill state, purged on terminal-step ok.
- `.snap/telemetry.ndjson` — append-only event log.

## Resume protocol

`/snap:ticket --resume --feature=01` reads `.snap/progress.json` via
`progress.sh resume --skill=ticket --story-id=<resolved>` — jumps to the
returned step.

## Acceptance check (whole skill)

- Manifest has `refs.tickets.sync_status = "synced"` after step-06.
- `.snap/tickets/{story_id}.json` validates against
  `_shared/schemas/tickets.schema.json` and contains ≥ 1 ticket.
- `progress.json.in_flight` no longer contains a `ticket` entry for the
  feature (purged by `progress.sh finish --status=ok`).
