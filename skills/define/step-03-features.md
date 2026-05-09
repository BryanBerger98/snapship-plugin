---
step: 03-features
next_step: 04-render
description: Capture features list with priorities and per-feature problem/solution/AC.
---

# step-03 — features

Decompose the vision into a prioritized feature list, then enrich each feature with
problem/solution/AC.

## Tasks

### Phase A — features list

1. **Ask features** via `AskUserQuestion` (free text, multiline):

   > "List the features that deliver the vision. One per line.
   > Format: `<short title>` (priority: must|should|could)."

   Parse each line. Reject lines without a recognized priority — re-ask with the
   parsing error shown.

2. **Assign feature_id**: starting from `01-` (or N+1 if extension mode finds existing
   features). Slug is kebab-case of the title (`Sign-up with email` → `signup-email`).
   Pad sequence to 2 digits (`01-`, `02-`, …, `99-`).

3. **Validate**:
   - At least 1 feature.
   - At least 1 feature has priority `must`.
   - No duplicate `feature_id`.
   - Each title is at least 3 chars.

4. **Confirm** the list back to the user via `AskUserQuestion`:
   - "Looks right — proceed"
   - "Edit the list" (loop back to step A.1)

### Phase B — per-feature enrichment

For each feature in priority order (`must` → `should` → `could`), ask:

1. **Problem statement** (free text, ≥30 chars, must mention "who" or a persona name).
2. **Solution overview** (free text, 3-5 sentences).
3. **Acceptance criteria** (free text, one per line, prefix `AC-N`). Parse into
   `{ ac_id, ac_text }`. At least 1 AC required.
4. **In scope** (free text).
5. **Out of scope** (free text — push the user to be specific; vague answers like "the
   rest" are rejected).
6. **Wireframe references** (optional — list of expected screen IDs; can be filled
   later by `/wireframe`).

After each feature, ask `AskUserQuestion`:
- "Continue with next feature"
- "Save and exit (remaining features → drafts)"

Drafts skip Phase B; their PRDs are rendered with placeholder sections marked
`<TBD — fill via /define --resume --feature=NN-slug>`.

### Phase C — cache

Update `.claude/product/.define-state.json`:

```json
{
  "step": "03-features",
  "features": [
    {
      "feature_id": "01-auth",
      "feature_title": "...",
      "feature_status": "draft",
      "priority": "must",
      "problem_statement": "...",
      "solution_overview": "...",
      "acceptance_criteria": [{ "ac_id": "1", "ac_text": "..." }],
      "in_scope": "...",
      "out_of_scope": "...",
      "wireframes": []
    }
  ]
}
```

### Phase D — progress

```bash
bash skills/_shared/update-progress.sh \
  --project-root="$PWD" \
  --feature-id=_global \
  --step-num=03 \
  --step-name=features \
  --status=ok \
  --skill=define
```

## Acceptance check

- `features` array has ≥ 1 entry.
- Every feature with `feature_status = "refined"` (i.e. enriched in Phase B) has all
  required fields populated.

## Next step

→ `step-04-render.md`
