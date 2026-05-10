---
step: 02-analyze
next_step: 03-confirm
description: AI groups indexed pages into proposed domains + journeys + page→target mapping. Emits proposed_structure JSON for user review.
---

# step-02 — analyze

Cluster pages from `step-01` index into a proposed snap hierarchy.

## Tasks

1. **Read index**:
   ```bash
   INDEX_FILE=".claude/product/.doc-import-index.ndjson"
   PAGE_COUNT=$(wc -l < "$INDEX_FILE" | tr -d ' ')
   ```

2. **Read full content** of each indexed page (chunk by chunk to fit context):
   For each `page_id` in the index, fetch body via
   `docs-adapter --action=get --page-id=...`. Cache to
   `.claude/product/.doc-import-cache/{page_id}.md`.

   Skip pages already cached (idempotent re-entry).

3. **AI clustering pass** (single-shot, you do this — no subagent):
   Read titles + first ~500 chars of each page. Cluster into domains using these
   heuristics:
   - **Domain** = high-level product area (auth, dashboard, billing, settings).
     2-7 domains is a healthy split for typical projects.
   - **User journey** under a domain = a user-facing flow with start + end
     (`Login Flow`, `Signup Flow`, `Password Reset`). One journey can be
     synthesized from multiple legacy pages covering the same flow.
   - Slug for each domain/journey: kebab-case, ≤30 chars.
   - Pages that don't fit any clear cluster → `unmapped_pages[]`.

4. **Emit proposed structure** as JSON to
   `.claude/product/.doc-import-proposal.json`:
   ```json
   {
     "strategy": "synthesize",
     "page_count": 42,
     "proposed_structure": {
       "auth": {
         "title": "Authentication",
         "source_pages": ["pid-1","pid-3","pid-7"],
         "journeys": {
           "login-flow": {
             "title": "Login Flow",
             "source_pages": ["pid-1","pid-3"],
             "synthesized_excerpt": "Login uses email + password. 2FA optional via TOTP. ..."
           },
           "signup-flow": {
             "title": "Signup Flow",
             "source_pages": ["pid-7"],
             "synthesized_excerpt": "Signup requires email verification. ..."
           }
         }
       }
     },
     "unmapped_pages": [
       { "page_id": "pid-99", "title": "Random notes", "reason": "no clear domain" }
     ]
   }
   ```

   `synthesized_excerpt` ≈ 1-3 sentences summarizing the journey from source
   content. Used in step-03 confirm UI to give the user a sniff test before
   committing.

5. **Sanity rules** (fail loud if violated — bad analysis = abort):
   - Every `source_pages[]` entry exists in the index.
   - No page appears under multiple journeys.
   - At least 1 domain proposed.
   - `domain_slug` and `journey_slug` match `^[a-z0-9][a-z0-9-]*$`.

6. **Print summary to user** (table form):
   ```
   Proposed import (strategy=synthesize):
     auth (3 pages → 2 journeys: login-flow, signup-flow)
     dashboard (5 pages → 1 journey: overview)
   Unmapped: 1 page (pid-99: "Random notes")
   ```

## Acceptance check

- `.doc-import-proposal.json` exists and parses.
- All sanity rules pass.

## Next step

→ `step-03-confirm.md` (user review). In `--auto` mode, step-03 still runs but
short-circuits to acceptance.
