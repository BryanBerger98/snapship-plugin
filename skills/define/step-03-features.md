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

2. **Assign story_id**: starting from `01-` (or N+1 if extension mode finds existing
   features). Slug is kebab-case of the title (`Sign-up with email` → `signup-email`).
   Pad sequence to 2 digits (`01-`, `02-`, …, `99-`).

3. **Validate**:
   - At least 1 feature.
   - At least 1 feature has priority `must`.
   - No duplicate `story_id`.
   - Each title is at least 3 chars.

4. **Confirm** the list back to the user via `AskUserQuestion`:
   - "Looks right — proceed"
   - "Edit the list" (loop back to step A.1)

### Phase B — per-feature enrichment

For each feature in priority order (`must` → `should` → `could`), batch
prompts in **3-5 `AskUserQuestion` calls** (max 4 questions per call). This
replaces the previous 8-9 sequential calls per feature.

**Short-circuit CLI parent epic** (read once, applies to every feature in the run) :

```bash
cli_epic=$(bash skills/_shared/define-state.sh get cli_parent_epic_id \
  --project-root="$PWD")
```

If `cli_epic` non-empty → `parent_epic_id="$cli_epic"`, `parent_epic_pending=false`
on every feature. Skip the Parent Epic question in Call 2 below (replace by the
fixed value).

#### Call 1 — open description (4 free-text questions)

1. **Problem statement** (free text, ≥30 chars, must mention "who" or a persona name).
2. **Solution overview** (free text, 3-5 sentences).
3. **In scope** (free text).
4. **Out of scope** (free text — push the user to be specific; vague answers like
   "the rest" are rejected).

#### Call 2 — structured choices (4 questions, mixed types)

1. **Acceptance criteria** (free text, one per line, prefix `AC-N`). Parse into
   `{ ac_id, ac_text }`. At least 1 AC required.
2. **Wireframe references** (optional — list of expected screen IDs; can be filled
   later by `/wireframe`).
3. **Parent Epic** (multiSelect: false) — **skip this question if `cli_epic` was
   set above** :
   > "Cette feature fait-elle partie d'un Epic parent ?"
   > - "Oui — j'ai déjà un Epic identifié (saisir l'ID plateforme)"
   > - "Oui — l'Epic n'existe pas encore (sera créé par `/snap:ticket`)"
   > - "Non — feature autonome"
4. **Domains impacted** (multi-select) :
   - Pre-load existing domains via
     `bash skills/_shared/taxonomy-state.sh list-domains --project-root="$PWD"` and
     use them as predefined options.
   - The user may also add a new domain via free input — capture the human
     title, auto-slug kebab. Reject the slug if it already exists with a
     different title.
   - ≥1 domain required.

#### Sub-call 2b — parent epic detail (conditional, 1 question)

Only fire if Call 2.3 answer ≠ « Non » :

- "Oui avec ID" → free text `parent_epic_id` (e.g. `#42`, `AUTH-1`, `&12`). No
  regex validation here — `/snap:ticket` will validate against the target
  platform.
- "Oui à créer" → free text `parent_epic_title`. Cache for `/snap:ticket` which
  will create the Epic then link-parent.

Persist on the feature object :
```json
{"parent_epic_id": "AUTH-1"}                                                  // existing
{"parent_epic_title": "Authentication platform", "parent_epic_pending": true} // pending
```

#### Call 3 — journeys per chosen domain (≤4 questions per call, multi-select each)

For each domain in `feature.domains`, build one multi-select question :

- Title : "Which journeys are impacted in domain `<title>` ?"
- Options : existing journeys (via
  `bash skills/_shared/taxonomy-state.sh list-journeys "$domain" --project-root="$PWD"`)
  plus "create new journey" free input.

Group up to **4 domains per `AskUserQuestion` call**. If the feature touches >4
domains, fire a second Call 3 with the remaining ones.

Persist as `impacted_journeys: [{domain, journey_slug, journey_title, is_new}, …]`.
New (yet-uncreated) journeys are kept in the state file but not pushed to the
doc platform until step-05-publish (which calls `lookup-or-create-page`).

#### Call 4 — control flow (1 question)

```text
"Done with this feature — continue with next, or save and exit?"
- "Continue with next feature"
- "Save and exit (remaining features → drafts)"
```

Drafts skip Phase B; their PRDs are rendered with placeholder sections marked
`<TBD — fill via /define --resume --story=NN-slug>`.

**Call count summary** : 3 mandatory + 1 conditional + 1 control + (extra Call 3
batches if >4 domains) ≈ **4-5 calls per feature** vs 8-9 previously.

### Phase C — cache

For each feature collected in Phase A/B:
```bash
bash skills/_shared/define-state.sh add-feature '{
  "story_id": "01-auth",
  "feature_title": "...",
  "feature_status": "draft",
  "priority": "must",
  "problem_statement": "...",
  "solution_overview": "...",
  "acceptance_criteria": [{"ac_id":"1","ac_text":"..."}],
  "in_scope": "...",
  "out_of_scope": "...",
  "wireframes": [],
  "parent_epic_id": "AUTH-1",
  "parent_epic_title": null,
  "parent_epic_pending": false,
  "domains": ["auth"],
  "impacted_journeys": [
    {"domain": "auth", "journey_slug": "login-flow", "journey_title": "Login Flow", "is_new": false}
  ]
}' --project-root="$PWD"
```

`parent_epic_id` est utilisé tel quel par step-04 (écrit dans
`manifest.parent_epic_id`). `parent_epic_pending=true` signale à
`/snap:ticket` qu'il faut créer l'Epic avant la User Story (mode
hierarchical strict — Phase D step-03b).

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
bash skills/_shared/progress.sh step \
  --project-root="$PWD" \
  --skill=define \
  --story-id=_global \
  --step-num=03 \
  --step-name=features \
  --status=ok
```

## Acceptance check

- `features` array has ≥ 1 entry.
- Every feature with `feature_status = "refined"` (i.e. enriched in Phase B) has all
  required fields populated, plus `domains` non-empty and `impacted_journeys`
  non-empty (v0.2).

## Next step

→ `step-04-render.md`
