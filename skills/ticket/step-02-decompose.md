---
step: 02-decompose
next_step: 03-enrich
description: Break feature into atomic stories (5-30min, 1-5 files) with one AC per story.
---

# step-02 — decompose

Convert the feature PRD into a list of atomic stories sized for `/develop` to land
each in a single commit.

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
     --feature-id="$feature_id" \
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

6. **Stash** the draft tickets in
   `.snap/tickets/${feature_id}.draft.json` (cleared by step-06 on success).
   Do **not** call the platform yet.

7. **Append progress**:
   ```bash
   bash skills/_shared/progress.sh step \
     --project-root="$PWD" \
     --skill=ticket \
     --feature-id="$feature_id" \
     --step-num=02 \
     --step-name=decompose \
     --status=ok
   ```

## Failure handling

- AC has no obvious story → ask user to clarify, do not synthesize.
- All stories estimated > 30 min → surface and re-prompt for sub-decomposition.

## Acceptance check

- ≥ 1 story per AC.
- Every story has `local_id`, `title`, `ac_id`, `files`.

## Next step

→ `step-03-enrich.md`
