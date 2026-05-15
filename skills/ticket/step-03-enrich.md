---
step: 03-enrich
next_step: 04-format
description: Run parallel agents (codebase, docs, websearch) to enrich each story body.
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

4. **Classify ticket type** — for each story, set `type ∈ {user-story, bug, epic}`
   based on title + AC + scope. Default `user-story`. Heuristic prompt for the
   enrichment agent (or local rule-based classifier):

   - **bug** — title contains "fix"/"bug"/"regression"/"crash"/"broken"; AC reads
     like "should no longer …" / "stops failing when …"; story restores prior
     behavior rather than adding capability.
   - **epic** — story aggregates ≥ 3 child stories explicitly listed; spans ≥ 2
     domains; `files` empty or extremely broad ("multiple modules").
   - **user-story** — anything else (default).

   Persist `type` on each story before format step. step-04 reads it to pick the
   right template.

5. **Update draft file** in-place:
   `.snap/tickets/${feature_id}.draft.json`.

6. **Append progress**:
   ```bash
   bash skills/_shared/progress.sh step \
     --project-root="$PWD" \
     --skill=ticket \
     --feature-id="$feature_id" \
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

- Every story has a `context` block (possibly with empty fields).
- Every story has `type ∈ {user-story, bug, epic}`.

## Next step

→ `step-04-format.md`
