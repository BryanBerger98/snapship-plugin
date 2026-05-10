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
7. **Domains impacted** (v0.2 — multi-select `AskUserQuestion` + free input):
   - Read existing domains from cache:
     ```bash
     bash skills/_shared/domains-state.sh list-domains --project-root="$PWD"
     ```
   - Present them as multi-select options. Allow user to add a new domain (free
     input → ask title humain, auto-slug kebab). Reject slug if it already
     exists with a different title.
   - Persist as `domains: [<slug>, …]` on the feature object. ≥1 domain required.

8. **Journeys impacted** (v0.2 — per domain chosen in step 7):
   For each domain in `feature.domains`:
   - List existing journeys via:
     ```bash
     bash skills/_shared/domains-state.sh list-journeys "$domain" --project-root="$PWD"
     ```
   - Multi-select existing + free input ("create new journey: title → slug auto").
   - Persist as `impacted_journeys: [{domain, journey_slug}, …]`.

   New (yet-uncreated) journeys are recorded in state file but not pushed to the
   doc platform until step-05-publish (which calls `lookup-or-create-page`).

After each feature, ask `AskUserQuestion`:
- "Continue with next feature"
- "Save and exit (remaining features → drafts)"

Drafts skip Phase B; their PRDs are rendered with placeholder sections marked
`<TBD — fill via /define --resume --feature=NN-slug>`.

### Phase C — cache

For each feature collected in Phase A/B:
```bash
bash skills/_shared/define-state.sh add-feature '{
  "feature_id": "01-auth",
  "feature_title": "...",
  "feature_status": "draft",
  "priority": "must",
  "problem_statement": "...",
  "solution_overview": "...",
  "acceptance_criteria": [{"ac_id":"1","ac_text":"..."}],
  "in_scope": "...",
  "out_of_scope": "...",
  "wireframes": [],
  "domains": ["auth"],
  "impacted_journeys": [
    {"domain": "auth", "journey_slug": "login-flow", "journey_title": "Login Flow", "is_new": false}
  ]
}' --project-root="$PWD"
```

`is_new: true` flags journeys that don't exist yet on the doc platform —
step-05-publish will create them with an empty body (filled later by the first
`/snap:doc-update` post-ship).

After all features added, run:
```bash
bash skills/_shared/define-state.sh validate --project-root="$PWD"
```
If validation fails, surface the error list to the user and re-enter Phase B for the
feature(s) flagged. Do not advance to step-04 until validation passes.

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
  required fields populated, plus `domains` non-empty and `impacted_journeys`
  non-empty (v0.2).

## Next step

→ `step-04-render.md`
