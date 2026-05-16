---
name: ticket
description: Decompose a feature PRD (or raw user input in --standalone) into atomic, dev-ready tickets with hierarchy (Epic / User Story / Task / Bug), enrich each with parallel agent research, format per platform, and push to GitHub/GitLab/JIRA/Linear via tickets-adapter. Blocks when tickets.platform = "none".
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, AskUserQuestion, Agent
---

# /snap:ticket — feature → tickets skill

Run after `/snap:define` (normal mode) **or** standalone (`--standalone`)
when a feature PRD does not exist yet and you want to push tickets
directly from raw input.

Output is a coherent ticket hierarchy on the configured tracker :
**Epic → User Story → Task / Bug**, with parent-child links pushed
strictly in dependency order.

## Prerequisites

- `/snap:init` ran and `tickets.platform != "none"` in `snap.config.json`.
  If `none`, the skill **blocks** :

  ```
  ERROR: tickets.platform is "none" — no tracker configured.
  Re-run /snap:init --force to set a tracker, then retry /snap:ticket.
  ```

- **Normal mode (no `--standalone`)** : `/snap:define` produced the
  feature manifest at `.snap/manifests/{story_id}.manifest.json` with
  `refs.prd.sync_status = "synced"`. PRD body is fetched from remote in
  step-01 if local staging is missing.

- **`--standalone` mode (v1.2)** : no manifest required, no PRD. Raw user
  input drives decomposition. **`story_type=epic` is refused** — Epics
  span features and require the manifest-backed flow (decision #5).

## When to use

- **Normal** : a manifest exists ; you want a numbered list of dev-ready
  stories (5-30 min, 1-5 files each) clustered into Epic/US/Task on the
  tracker.
- **Standalone** : quick capture of a bug list or a handful of tasks
  outside any feature — flat hierarchy, no Epic.
- **Resume** : `--resume` (`-r`) restarts from the last in-flight step
  recorded in `.snap/progress.json`.

## Pipeline

| #    | Step                       | Purpose |
|------|----------------------------|---------|
| 00   | `step-00-init.md`          | Parse args (`--standalone`, `--auto`, `--keep-runtime`), resolve `story_id` (skipped under standalone), load config, init ephemeral subject + EXIT-trap purge |
| 01   | `step-01-load.md`          | Snapshot live tracker context (capabilities + Epics + milestones + versions) into ephemeral cache ; load PRD (normal mode only) |
| 02   | `step-02-decompose.md`     | Break PRD into atomic stories (normal) **or** split raw input into candidate tickets (standalone) — drafts in ephemeral cache |
| 03   | `step-03-enrich.md`        | Parallel agents (codebase / docs / web) + classify `story_type ∈ {epic, user-story, task, bug}` |
| 03b  | `step-03b-hierarchy.md`    | Cluster Epic ↔ User Story ↔ Task ; validate parent-child matrix ; offer rattachement to existing tracker Epics |
| 03c  | `step-03c-metadata.md`     | Capability-gated milestone + `target_version` assignment per draft |
| 04   | `step-04-format.md`        | Render per `story_type` template, suggest `commit_type` + `branch_name`, Ajv-validate every draft |
| 05   | `step-05-push.md`          | Strict ordered push (Epic → US → Task/Bug → milestone → version), idempotent, blocks child if parent draft |
| 06   | `step-06-index.md`         | Promote drafts → `.snap/tickets/{fid}.json`, ack manifest, surface summary table, **mandatory ephemeral purge** |

## Args

```
/snap:ticket [--resume|-r] [--feature=NN-slug]
             [--platform=github|gitlab|jira|linear]
             [--max-stories=N] [--dry-run]
             [--standalone] [--auto] [--keep-runtime]
```

- `--feature` (required if multiple manifests, ignored under
  `--standalone`) : target `story_id` (partial-match supported).
- `--platform` : override `config.tickets.platform`.
- `--max-stories` : cap auto-decomposition (default 12).
- `--dry-run` : format + log but skip the tracker write.
- `--standalone` : skip PRD load + manifest ack ; drive decomposition
  from raw user input. **Refuses any draft classified `story_type=epic`**
  (decision #5).
- `--auto` (opt-in) : run hierarchy clustering + metadata in bulk via
  inline LLM heuristics instead of step-by-step prompts. Warns explicitly
  on every auto-assigned parent / milestone / version. User can fall
  back to interactive on the final confirmation prompt.
- `--keep-runtime` : **debug only** — preserve the ephemeral subject at
  `.snap/.runtime/<subject-id>/` instead of purging it at step-06. The
  path is surfaced in the summary so you can inspect drafts/clustering.

## Outputs

Local (persistent — references to remote) :

- **Normal mode** : `.snap/tickets/{story_id}.json` — cached tickets
  array (schema `tickets.schema.json`).
- **Normal mode** : `.snap/manifests/{story_id}.manifest.json` —
  `refs.tickets` populated via `sync-push.sh ack`.
- **Standalone mode** : no persistent local artefact — tracker is the
  single source of truth ; summary table is the user-visible output.

Remote (single source of truth) :

- Tickets / issues on GitHub / GitLab / JIRA / Linear (URLs cached
  above), parent-child links applied strictly post-create.

Local (runtime — gitignored, purged at end of skill) :

- `.snap/.runtime/<subject-id>/drafts.json` — drafts mid-flight (purged
  by EXIT trap unless `--keep-runtime`).
- `.snap/.runtime/<subject-id>/tracker-context.json` — live tracker
  snapshot.
- `.snap/progress.json` — in-flight skill state, purged on terminal-step
  ok.
- `.snap/telemetry.ndjson` — append-only event log.

## Resume protocol

`/snap:ticket --resume --feature=01` reads `.snap/progress.json` via
`progress.sh resume --skill=ticket --story-id=<resolved>` — jumps to the
returned step. Push idempotence (lookup-by-title before create) means a
mid-step-05 crash followed by `--resume` finishes the unpushed children
without duplicates.

`--resume` is **not supported under `--standalone`** — no persistent
story_id to anchor the run.

## Examples

```bash
# Normal flow after /snap:define produced manifest 01-auth.
/snap:ticket --feature=01

# Resume after a crash mid-step-05.
/snap:ticket --resume --feature=01

# Bulk mode : let the inline LLM cluster + assign metadata.
/snap:ticket --feature=01 --auto

# Standalone bug capture — no manifest, no PRD.
/snap:ticket --standalone

# Dry-run to inspect rendered bodies without touching the tracker.
/snap:ticket --feature=01 --dry-run

# Debug : keep the ephemeral subject for inspection after the run.
/snap:ticket --feature=01 --keep-runtime
```

## Acceptance check (whole skill)

- **Normal mode** :
  - Manifest has `refs.tickets.sync_status = "synced"` after step-06.
  - `.snap/tickets/{story_id}.json` validates against
    `_shared/schemas/tickets.schema.json` and contains ≥ 1 ticket.
- **Standalone mode** :
  - No `tickets.json`, no manifest mutation.
  - Summary table surfaced with `local_id → platform_id → URL → status`.
- **Always** :
  - Every pushed ticket carries `story_type` ∈ enum + parent-child links
    matching the v1.2 matrix.
  - `.snap/.runtime/<subject-id>/` purged (unless `--keep-runtime`).
  - `progress.json.in_flight` no longer contains a `ticket` entry.
