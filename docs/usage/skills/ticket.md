# `/snap:ticket` — feature / raw input → ticket hierarchy

Decomposes a feature PRD (normal mode) or a raw user prompt (`--standalone`)
into an Epic / User Story / Task / Bug hierarchy, enriches each draft with
parallel research, formats per platform, and pushes everything to the
configured tracker in strict dependency order.

## What it does

Turns a feature PRD — or raw input in `--standalone` — into a coherent ticket
hierarchy on the configured tracker:

- **Epic** (no branch, no commit — narrative grouping)
- **User Story** (branch + PR, atomic dev unit)
- **Task** (branch + PR, optionally reusing the parent User Story branch)
- **Bug** (branch + PR)

Plus orthogonal metadata: `milestone` (tracker-native) and `target_version`
(capability-gated).

## When to use it

- **Normal mode** — `/snap:define` has produced a feature manifest under
  `.snap/manifests/{story_id}.manifest.json` and you want it decomposed.
- **Standalone mode** — quick capture of a bug list or a handful of tasks
  outside any feature (no manifest, no PRD). **Refuses Epic drafts** — Epics
  span features and require the manifest-backed flow.
- **Resume** — `--resume` after a crash mid-flow.

## Prerequisites

- `/snap:init` ran and `tickets.platform != "none"` in `snap.config.json`. If
  `none`, the skill blocks with an explicit error.
- **Normal mode**: a feature manifest at
  `.snap/manifests/{story_id}.manifest.json` with `refs.prd.sync_status =
  "synced"`. The PRD body is fetched live from the doc platform when local
  staging is missing.
- **Standalone mode**: no manifest, no PRD — just raw user input.

## Modes

| Mode             | Trigger                       | PRD required | Allows `epic` story_type |
|------------------|-------------------------------|--------------|--------------------------|
| `interactive`    | default (no flag)             | yes (normal) | yes                      |
| `--auto`         | opt-in flag                   | yes (normal) | yes                      |
| `--standalone`   | opt-in flag                   | no           | **no** (refused)         |

- **`interactive`** — every clustering, parent assignment, milestone and
  version pick is confirmed via `AskUserQuestion`. Step-by-step prompts.
- **`--auto`** — inline-LLM heuristics drive hierarchy clustering and
  metadata assignment in bulk. Each auto-decision is warn-logged. A final
  bulk-confirm prompt lets you bail out to `interactive`.
- **`--standalone`** — flat hierarchy, no PRD, no manifest mutation. Any
  draft classified as `story_type=epic` is rejected at step-03 with an
  explicit message (Epics belong to the manifest-backed flow).

## Syntax

```
/snap:ticket [--resume|-r] [--story-id=NN-slug]
             [--platform=github|gitlab|jira|linear]
             [--max-stories=N] [--dry-run]
             [--standalone] [--auto] [--keep-runtime]
```

## Flags

| Flag                              | Effect                                                                                        |
| --------------------------------- | --------------------------------------------------------------------------------------------- |
| `--resume` / `-r`                 | Resume at the last in-flight step recorded in `progress.json` (not supported in standalone).  |
| `--story-id=NN-slug`              | Target an existing manifest by `story_id` (partial-match supported). Required when several manifests exist. |
| `--platform=github\|gitlab\|jira\|linear` | Override `config.tickets.platform`.                                                  |
| `--max-stories=N`                 | Cap auto-decomposition (default: 12).                                                         |
| `--dry-run`                       | Format and log every draft, skip the tracker write.                                           |
| `--standalone`                    | No manifest, no PRD — raw user input drives decomposition. Refuses `epic` drafts.             |
| `--auto`                          | Inline-LLM heuristics for hierarchy + metadata. Warn-log every auto-decision.                 |
| `--keep-runtime`                  | Debug only — preserve `.snap/.runtime/<subject-id>/` instead of purging at step-06.           |

Downstream skills (`/snap:develop`, `/snap:qa`, `/snap:doc-update`) take
`--ticket=<platform_id>` to target a tracker ticket directly; `/snap:ticket`
itself only takes `--story-id=` since it is the producer of those tickets.

## Pipeline

| #    | Step                       | Role                                                                                       |
|------|----------------------------|--------------------------------------------------------------------------------------------|
| 00   | `step-00-init.md`          | Parse args, resolve `story_id` (skipped in standalone), init ephemeral subject + EXIT-trap purge. |
| 01   | `step-01-load.md`          | Snapshot live tracker context (capabilities + Epics + milestones + versions) into the ephemeral cache. Load PRD (normal mode only). |
| 02   | `step-02-decompose.md`     | Break PRD into atomic stories (normal) or split raw input into candidate tickets (standalone). |
| 03   | `step-03-enrich.md`        | Parallel agents (codebase / docs / web) + classify `story_type ∈ {epic, user-story, task, bug}`. |
| 03b  | `step-03b-hierarchy.md`    | Cluster Epic ↔ User Story ↔ Task ; validate the parent-child matrix ; offer rattachement to existing tracker Epics. |
| 03c  | `step-03c-metadata.md`     | Capability-gated `milestone` + `target_version` assignment per draft.                       |
| 04   | `step-04-format.md`        | Render per `story_type` template, suggest `commit_type` + `branch_name`, Ajv-validate every draft. |
| 05   | `step-05-push.md`          | Strict ordered push, idempotent, blocks children if their parent is still a draft.          |
| 06   | `step-06-index.md`         | Normal mode: promote drafts to `.snap/tickets/{story_id}.json` + ack manifest. Always: surface summary table, **mandatory ephemeral purge**. |

## Push order (step-05)

Strict dependency order — children are blocked until their parent gets a
`platform_id`:

1. **Epics** (`tracker_create_ticket`)
2. **User Stories** with resolved `parent_epic_id` (if any)
3. **Tasks / Bugs** with resolved `parent_story_id` or `parent_epic_id`
4. **Milestones** assigned (`tracker_set_milestone`)
5. **Target versions** assigned (`tracker_set_version`, capability-gated)

**Idempotence guarantees**:

- Before every create, the adapter looks up by title + parent hint and
  skips if the ticket already exists.
- A mid-step-05 crash followed by `--resume` finishes the unpushed
  children without duplicates.
- A re-run of the whole skill on the same input produces no extra
  tracker writes (lookup-by-title + commit-aware checks).

If a parent create fails, every child is skipped with an explicit
message (`Ticket <child>: parent <parent> not pushed`) instead of being
created as an orphan.

## Hierarchy notes (v1.2)

- **Epic** — no branch, no commit. Refused in `--standalone`.
- **User Story** — branch + PR (one dev cycle per US).
- **Task** — branch + PR. When parented to a User Story, `/snap:develop`
  reuses the parent US branch; otherwise it gets its own.
- **Bug** — branch + PR. Can have Task children for technical sub-work;
  Bug-of-Bug is rejected.

Detailed parent-child matrix and capability flags live in
[`docs/contributing/architecture.md`](../../contributing/architecture.md).
Native routing (Issue Types, Projects v2 fields on GitHub) is inherited
from v1.1 and gated by adapter capabilities — same architecture doc for
the full table.

## Outputs

Local (persistent — references to remote, normal mode only):

- `.snap/tickets/{story_id}.json` — cached ticket array validated against
  `_shared/schemas/tickets.schema.json`.
- `.snap/manifests/{story_id}.manifest.json` — `refs.tickets` populated
  via `sync-push.sh ack`.

Local (persistent — standalone mode): no persistent artefact. The
tracker is the single source of truth; the summary table is the
user-visible output.

Remote (single source of truth):

- Tickets on GitHub / GitLab / JIRA / Linear with parent-child links
  applied strictly post-create. URLs cached locally in normal mode.

Local (runtime — gitignored, purged at end of skill):

- `.snap/.runtime/<subject-id>/drafts.json` — drafts mid-flight.
- `.snap/.runtime/<subject-id>/tracker-context.json` — live tracker
  snapshot (capabilities + Epics + milestones + versions).
- `.snap/progress.json` — in-flight skill state.
- `.snap/telemetry.ndjson` — append-only event log.

The ephemeral subject is purged by an `EXIT` trap on success **and**
failure unless `--keep-runtime` is set.

## Resume protocol

```bash
/snap:ticket --resume --story-id=01
```

Reads `.snap/progress.json` via
`progress.sh resume --skill=ticket --story-id=<resolved>` and jumps to
the returned step. `--resume` is **not supported under `--standalone`**
— no persistent `story_id` to anchor the run.

## Examples

```bash
# Normal flow after /snap:define produced manifest 01-auth.
/snap:ticket --story-id=01

# Resume after a crash mid-step-05.
/snap:ticket --resume --story-id=01

# Bulk mode: let the inline LLM cluster + assign metadata.
/snap:ticket --story-id=01 --auto

# Standalone capture — no manifest, no PRD, no Epic allowed.
/snap:ticket --standalone

# Dry-run to inspect rendered bodies without touching the tracker.
/snap:ticket --story-id=01 --dry-run

# Debug: keep the ephemeral subject after the run.
/snap:ticket --story-id=01 --keep-runtime
```

## Next step

`/snap:wireframe` or `/snap:design` for User Stories with UI, then
`/snap:develop --ticket=<platform_id>` straight from the tracker URL or
ID surfaced in the summary table.
