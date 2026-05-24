---
step: 03b-hierarchy
next_step: 03c-metadata
description: Cluster drafts into Epic ↔ User Story ↔ Task relationships ; validate parent-child matrix ; offer rattachement to existing tracker Epics.
---

# step-03b — hierarchy

Resolve parent-child relationships across all drafts produced by step-03.
Output is `parent_epic_id` and/or `parent_story_id` set on every applicable
draft, plus optional rattachement (`parent_epic_id` = platform_id of an
existing tracker Epic loaded into `tracker-context.json` at step-01).

**This step always runs in the main agent context** — multi-turn user
dialogue is incompatible with subagent fan-out.

## Inputs

- `.snap/.runtime/<SUBJECT_ID>/drafts.json` — drafts from step-03 carrying
  `story_type`, `context`, optional `hierarchy_hint`.
- `.snap/.runtime/<SUBJECT_ID>/tracker-context.json` — Epic list snapshotted
  at step-01 (used for rattachement proposals).

## Parent-child matrix (decision #7e)

Allowed parent transitions :

| Child `story_type` | Allowed parent `story_type` | Notes |
|---|---|---|
| `epic` | (none) | Epics are roots. |
| `user-story` | `epic` *(optional)* | Optional rattachement to an Epic. |
| `task` | `user-story`, `epic`, *(none)* | Standalone tasks allowed. |
| `bug` | *(none — flat)* | Bugs are always flat in v1.2 — never nested under Epic/US/Task. |

Any other transition is a hard error :

> `ERROR: invalid hierarchy — <child story_type> cannot be parent of <parent story_type>`

Bug→anything as a parent is forbidden. Task→Task is forbidden. Cycles are
forbidden.

## Modes

### Interactive (default)

1. **Cluster proposal** — group drafts by inferred Epic. Heuristics :
   - Drafts of `story_type=epic` are roots.
   - Drafts of `story_type=user-story` that share an Epic-like noun in their
     title (or whose `context.codebase` mentions a shared module) cluster
     under the same draft Epic if one exists ; else surfaces as candidates
     for rattachement to a tracker Epic.
   - Drafts of `story_type=task` cluster under the most-related User Story
     in the same batch (heuristic on shared `files` / shared scope).

2. **Surface clustering to the user** via `AskUserQuestion` (multiSelect
   when applicable) — one prompt per ambiguous decision :
   - « Tâche `<title>` semble lier à User Story `<title>` — confirmer ? »
   - « User Story `<title>` correspond à Epic tracker `<existing_epic>` —
     rattacher ? »
   - « Bug `<title>` standalone (pas de parent v1.2) — OK ? »

3. **Apply user decisions** — write `parent_epic_id` / `parent_story_id`
   onto each draft. When rattachement points to an existing tracker Epic
   (loaded from tracker-context), use its `platform_id` ; otherwise leave
   `parent_epic_id` referencing the draft `local_id` of an unpublished
   Epic — step-05 resolves the platform_id post-create.

4. **Validate matrix** — run the parent-child matrix above against every
   resolved relationship. Fail-clean on the first violation with the rule
   that was broken.

### `--auto` (bulk)

1. Spawn `snap-ticket-classifier` in `auto` mode (sub-task `cluster`) :

   ```
   subagent_type: snap-ticket-classifier
   prompt: |
     {raw_input}: <JSON dump of current drafts.json>
     {tracker_context}: <contents of .snap/.runtime/<SUBJECT_ID>/tracker-context.json>
     {conventions}: <relevant CLAUDE.md excerpts>
     {mode}: "auto"
     {parent_hint}: <story_id if normal mode, else null>
   ```

   Parse the last ` ```json ` fence. Each returned ticket carries
   `parent_epic_id` / `parent_story_id` filled per the parent-child matrix
   the classifier enforces internally.

2. Surface the proposed mapping as a single table to the user with one
   `AskUserQuestion` :
   - « Clustering proposé OK pour les N tickets ? »
   - « Éditer (retomber en mode interactif) »

3. Warn explicitly when `confidence < 0.7` per ticket — surface the
   classifier `rationale` + `warnings[]` to justify each parent guess.
   If the user falls back to interactive, drop the classifier output and
   re-run the interactive path on the original drafts.

## Tasks

1. **Read drafts + tracker context** from the ephemeral cache.
2. **Compute proposed clustering** (heuristics above ; LLM in `--auto`).
3. **Resolve relationships** through interactive or auto path. Route the
   confirmation through `ask-or-default.sh` so that `auto_mode` (resolved in
   step-00 from `defaults.auto_mode` ∨ `--auto`/`-a`) auto-accepts the proposed
   clustering when truthy:
   ```bash
   choice=$(bash skills/_shared/ask-or-default.sh \
     --auto-mode="$auto_mode" \
     --question-id=confirm-clustering \
     --question="Clustering proposé OK pour les N tickets ?" \
     --options="accept,edit" --default=accept --header="Clustering")
   ```
   `accept` → keep the proposed mapping; `edit` → fall back to interactive.
4. **Validate parent-child matrix** — fail-clean on violation.
5. **Write updated drafts** back to
   `.snap/.runtime/<SUBJECT_ID>/drafts.json` with `parent_epic_id` /
   `parent_story_id` populated where applicable.
6. **Append progress** :
   ```bash
   bash skills/_shared/progress.sh step \
     --project-root="$PWD" \
     --skill=ticket \
     --story-id="$story_id" \
     --step-num=03b \
     --step-name=hierarchy \
     --status=ok
   ```

## Failure handling

- Matrix violation → fail-clean with the offending pair surfaced.
- `--auto` flag set in non-TTY context where interactive fallback is
  impossible → fail-clean with pointer to drop `--auto` for manual
  clustering.
- Tracker-context missing (step-01 failure) → degrade to flat hierarchy
  (no rattachement proposals), still validate matrix.

## Acceptance check

- Every draft has `story_type` and (when applicable) `parent_epic_id` /
  `parent_story_id` set.
- Parent-child matrix passes for all relationships.
- `--standalone` mode : no Epic drafts (refused at step-03), so this step
  is effectively a no-op for hierarchy but still validates the flat matrix.

## Next step

→ `step-03c-metadata.md`
