---
step: 03-enrich
next_step: 03b-hierarchy
description: Run parallel agents (codebase, docs, websearch) to enrich each draft + classify `story_type` (epic/user-story/task/bug).
---

# step-03 — enrich

Hydrate every draft story with the context a developer needs to land it: existing
code references, library docs, external research.

## Agent fan-out

Send **one message with N Agent tool calls** so the runs execute in parallel
(per Claude Code parallel-tool-call rule):

| Agent | Subagent | When |
|-------|----------|------|
| Codebase exploration | `explore-codebase` | Always (find existing modules to extend, tests, related types) |
| Library docs | `explore-docs` | Story's `files` references a third-party lib (detected via package manifest) |
| Web search | `websearch` | Story body mentions an external service / API / pattern not in repo |

For a feature with N stories, you may issue up to `config.ai.max_parallel_agents`
parallel calls per round — chunk if needed.

## Per-agent prompt template

Each agent receives a self-contained prompt (it has no conversation context):

```
Story: <title>
Acceptance criterion: <ac_text>
Expected files: <list>
PRD problem: <problem>
PRD solution: <solution_overview>

Task: <agent-specific instruction>
Return: <≤ 200 words, the specific format>
```

### explore-codebase

> Task: locate existing modules in this repo that this story should extend or call.
> Return: file paths + 1-line description per match. Note any test fixtures already
> covering the AC.

### explore-docs

> Task: fetch authoritative docs for the libraries this story will use, focused on
> the API surface relevant to the AC.
> Return: the specific function / class / config option, with a short example.

### websearch

> Task: find 2-3 reputable references (RFC, vendor docs, well-known blog) for the
> external pattern referenced.
> Return: title + URL + 1-line takeaway each.

## Tasks

1. **Plan the fan-out**: build the agent-call list per story, respecting
   `config.ai.max_parallel_agents`.

2. **Issue parallel calls** in a single assistant message.

3. **Collect findings**: append a `context` block to each draft story:
   ```json
   {
     "context": {
       "codebase": "Found `auth/index.ts:42` already exposes `createUser`...",
       "docs": "https://stripe.com/docs/api/checkout/sessions/create — use `mode:'payment'`",
       "web": ["https://...", "..."]
     }
   }
   ```

4. **Classify `story_type`** — for each draft, set
   `story_type ∈ {epic, user-story, task, bug}` based on title + AC + scope.
   Default `user-story`. Heuristic (plug-in point for the
   `snap-ticket-classifier` subagent in Phase H — see
   [02-subagents-design](../../../.claude/plan/ticket-hierarchy-redesign/02-subagents-design.md)):

   - **epic** — aggregates ≥ 3 child stories explicitly listed ; spans ≥ 2
     domains ; `files` empty or extremely broad. **Forbidden in `--standalone`
     mode** (decision #5) — surface a fail-clean error and abort.
   - **bug** — title contains "fix"/"bug"/"regression"/"crash"/"broken" ; AC
     reads like "should no longer …" / "stops failing when …" ; story restores
     prior behavior rather than adding capability.
   - **task** — technical work without direct user value (build, CI tweak,
     dependency bump, refactor that does not change behavior). Often a child
     of a User Story or an Epic, but standalone tasks are allowed.
   - **user-story** — anything else (default). Adds user-facing capability.

5. **Active challenge** : for every draft classified as `task` that has no
   `parent_story_id` and no `parent_epic_id`, emit an explicit warning in the
   summary surfaced to the user :

   > « Task `<title>` isolée — confirmer absence d'User Story parent ? »

   The user resolves the prompt at step-03b (hierarchy clustering). Do not
   block here.

6. **Detect standalone vs hierarchy** : load
   `.snap/.runtime/<SUBJECT_ID>/tracker-context.json` ; if the Epic list is
   non-empty, mark `hierarchy_hint=true` in the cached drafts so step-03b
   surfaces possible parents.

7. **Update drafts in ephemeral cache** :
   ```bash
   echo "$drafts_json" | bash skills/_shared/cache-runtime.sh write \
     "$SUBJECT_ID" drafts.json --project-root="$PWD"
   ```

8. **Append progress**:
   ```bash
   bash skills/_shared/progress.sh step \
     --project-root="$PWD" \
     --skill=ticket \
     --story-id="$story_id" \
     --step-num=03 \
     --step-name=enrich \
     --status=ok
   ```

## Failure handling

- Agent returns empty / fails → record `context.<agent>_error` with the message; do
  not block the pipeline (devs can still pick up the ticket without enrichment).
- All three agents fail for a story → mark the story `context_status: "minimal"` and
  continue.

## Acceptance check

- Every draft has a `context` block (possibly with empty fields).
- Every draft has `story_type ∈ {epic, user-story, task, bug}`.
- `--standalone` mode : zero drafts with `story_type=epic` (refused — decision #5).
- Drafts persisted in `.snap/.runtime/<SUBJECT_ID>/drafts.json`.

## Next step

→ `step-03b-hierarchy.md`
