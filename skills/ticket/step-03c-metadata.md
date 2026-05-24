---
step: 03c-metadata
next_step: 04-format
description: Assign milestone + target_version per draft (capability-gated, interactive or `--auto` LLM heuristic).
---

# step-03c — metadata

Attach optional tracker metadata to each draft : milestone (sprint / due-date
bucket) and `target_version` (release tag the work targets). Both are
**capability-gated** — if the platform does not support them, the
corresponding assignment is silently skipped with a single warn-once
emitted in the step-01 capability log.

## Inputs

- `.snap/.runtime/<SUBJECT_ID>/drafts.json` — drafts with hierarchy resolved
  by step-03b.
- `.snap/.runtime/<SUBJECT_ID>/tracker-context.json` — `capabilities`,
  `milestones`, `versions` snapshot.

## Capability gating

| Field | Required capability | Behaviour when unsupported |
|---|---|---|
| `milestone` | `supports_milestone=true` | Skip + warn-once |
| `target_version` | `supports_version=true` | Skip + warn-once |

For GitHub specifically, `supports_version=false` — `target_version` is
never assigned at push time (a separate Release post-merge is the
post-development convention). The capability log is the single source of
truth ; do not re-check per-platform here.

## Modes

### Interactive (default)

For each draft (skipping Epics for `target_version` — Epics span releases) :

1. Surface the available milestones (lookup ephemeral cache) via
   `AskUserQuestion` :
   - « Milestone pour `<title>` ? » — options : every milestone in
     `tracker-context.milestones[]` + « (aucun) ».
2. Surface the available versions via `AskUserQuestion` :
   - « target_version pour `<title>` ? » — options : every version in
     `tracker-context.versions[]` + « (aucune) ».
3. Apply user choices to the draft.

Both prompts are skippable per ticket — `(aucun/aucune)` leaves the field
empty.

### `--auto` (bulk)

1. Inline LLM proposes assignments based on heuristics — plug-in point for
   `snap-ticket-classifier` subagent in Phase H. Heuristic hints :
   - Match milestone by due date proximity to today + by name overlap with
     the draft title.
   - Match version by name overlap with the draft title or by being the
     newest unreleased version.
2. Emit explicit warn for each assigned milestone/version :
   > « Auto-assigned milestone=`<X>` to ticket=`<local_id>` — verify before push. »
3. Surface the final mapping table to the user with one `AskUserQuestion`
   en bloc :
   - « Metadata proposée OK ? »
   - « Éditer (retomber en mode interactif) »

## Tasks

1. **Read drafts + capabilities** from the ephemeral cache.
2. **Iterate over drafts** :
   - Skip `milestone` step when `supports_milestone=false`.
   - Skip `target_version` step when `supports_version=false` OR draft is
     `story_type=epic`.
   - Apply interactive or auto path per `auto_mode` (resolved in step-00 from
     `defaults.auto_mode` ∨ `--auto`/`-a`). Route the final confirmation
     through `ask-or-default.sh` so a truthy `auto_mode` auto-accepts:
     ```bash
     choice=$(bash skills/_shared/ask-or-default.sh \
       --auto-mode="$auto_mode" \
       --question-id=confirm-metadata \
       --question="Metadata proposée OK ?" \
       --options="accept,edit" --default=accept --header="Metadata")
     ```
3. **Write updated drafts** back to
   `.snap/.runtime/<SUBJECT_ID>/drafts.json` with `milestone` and
   `target_version` populated where applicable.
4. **Append progress** :
   ```bash
   bash skills/_shared/progress.sh step \
     --project-root="$PWD" \
     --skill=ticket \
     --story-id="$story_id" \
     --step-num=03c \
     --step-name=metadata \
     --status=ok
   ```

## Failure handling

- User picks a milestone/version not in the snapshot (rare — invalid input
  via `Other`) → reject with the list of valid options surfaced again.
- Network failure already handled at step-01 (this step works off the cached
  snapshot only).

## Acceptance check

- Every draft has been processed (decisions recorded or skipped).
- No draft has `target_version` set when `supports_version=false`.
- No draft has `milestone` set when `supports_milestone=false`.
- Epic drafts have no `target_version`.

## Next step

→ `step-04-format.md`
