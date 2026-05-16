---
step: 02-decompose
next_step: 03-enrich
description: Break feature PRD (or raw `--standalone` input) into atomic ticket candidates ; detect implicit multi-ticket inputs.
---

# step-02 — decompose

Convert the feature PRD (normal mode) **or** the raw user input
(`--standalone`) into a list of atomic ticket candidates sized for `/develop`
to land each in a single commit.

Drafts are written into the **ephemeral subject cache** at
`.snap/.runtime/<SUBJECT_ID>/drafts.json` — purged at step-06 regardless of
outcome (decision #2). No persistent draft file under `.snap/tickets/` is
created until promotion at step-06.

## Input source (v1.2)

| Mode | Source |
|---|---|
| Normal | `acceptance_criteria` array from step-01 PRD extraction |
| `--standalone` | Raw user input string (verbatim, `$USER_INPUT` in context) — split into multiple candidate tickets when the input contains conjunctions (`et`/`and`/`puis`/`then`), comma lists, bullet items (`- `/`* `/`1.`), or numbered phrasing |

For `--standalone` the heuristic for **implicit multi-ticket** :

- Split on bullet markers (`^\s*[-*]\s`, `^\s*\d+\.\s`).
- Split on top-level conjunctions when each clause has its own verb phrase.
- Single sentence → single candidate.
- Always offer the user a chance to merge/split via `AskUserQuestion` before
  writing drafts.

## Atomic-story heuristic

| Constraint | Threshold |
|------------|-----------|
| Estimated dev time | 5-30 min |
| Files touched | 1-5 |
| Acceptance criteria covered | 1 per story |
| Compile / typecheck breakage radius | local to story |

Reject any candidate story that:
- Spans > 5 files (suggests need to split).
- Mixes UI + DB migration + API contract (split into 3).
- Has > 1 AC (split per AC unless ACs are identical phrasings of one behaviour).

## Tasks

1. **Map AC → stories**: for each `acceptance_criteria` entry from step-01,
   draft a story (shape aligned with `tickets.schema.json` `local_id` field) :
   ```json
   {
     "local_id": "t-001",
     "title": "<imperative verb + object>, ≤ 70 chars",
     "ac_id": "1",
     "ac_text": "...",
     "estimated_min": 15,
     "files": ["src/auth/signup.ts", "src/auth/__tests__/signup.test.ts"],
     "depends_on": [],
     "labels": ["feature:01-auth"],
     "priority": "must",
     "estimated_size": "S",
     "scope": "backend",
     "status": "draft"
   }
   ```
   Persist `priority` / `estimated_size` / `scope` as **structured fields**
   (top-level keys), not labels. step-05 routes them to native GitHub primitives
   (Issue Type, Project v2 custom fields) when `tickets.github` is configured;
   otherwise the apply-metadata helper falls back to labels. The `feature:<id>`
   label is the only platform-agnostic grouping label kept by default
   (configurable via `tickets.github.label_fallback_prefixes`).
   `story.type` is set in step-03 (enrich/classify); it must NOT be inlined as a
   `type:<value>` label here.

2. **Apply naming**: derive `local_id` via `apply-naming.sh`:
   ```bash
   bash skills/_shared/apply-naming.sh ticket \
     --story-id="$story_id" \
     --sequence="$n"
   # → t-001, t-002, …
   ```

3. **Detect dependencies**: scan story bodies for cross-story references; populate
   `depends_on` with prior `local_id`s. The order in `tickets.json` determines
   dev order — sort topologically (must come before should before could; respect
   `depends_on`).

4. **Cap on `--max-stories`**: if the candidate list exceeds the cap, surface the
   overflow via `AskUserQuestion`:
   - "Split feature into a follow-up `/define --resume --feature=…` (recommended)"
   - "Continue and let me trim manually"

5. **Confirm with user** via `AskUserQuestion` (table preview, multiSelect false):
   - "Looks right — proceed to enrichment"
   - "Edit the list" (loop back to A.1, with the current draft as starting point)

6. **Stash drafts in ephemeral cache** :
   ```bash
   echo "$drafts_json" | bash skills/_shared/cache-runtime.sh write \
     "$SUBJECT_ID" drafts.json --project-root="$PWD"
   ```
   Drafts live ONLY in `.snap/.runtime/<SUBJECT_ID>/drafts.json` ; auto-purged
   by the step-00 trap. Do **not** call the platform yet, and do **not** write
   any persistent file under `.snap/tickets/`.

7. **Append progress**:
   ```bash
   bash skills/_shared/progress.sh step \
     --project-root="$PWD" \
     --skill=ticket \
     --story-id="$story_id" \
     --step-num=02 \
     --step-name=decompose \
     --status=ok
   ```

## Failure handling

- AC has no obvious story → ask user to clarify, do not synthesize.
- All stories estimated > 30 min → surface and re-prompt for sub-decomposition.

## Acceptance check

- `.snap/.runtime/<SUBJECT_ID>/drafts.json` exists with ≥ 1 candidate.
- Normal mode : ≥ 1 candidate per AC ; every entry has `local_id`, `title`,
  `ac_id`, `files`.
- `--standalone` mode : every candidate has `local_id`, `title` ; `ac_id`
  may be absent (no PRD).

## Next step

→ `step-03-enrich.md`
