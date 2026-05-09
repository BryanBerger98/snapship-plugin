---
step: 04-render
next_step: 05-publish
description: Render prd-global.md and per-feature PRDs from templates using cached state.
---

# step-04 — render

Materialize the markdown PRDs from the cached state and the bundled templates.

## Inputs

- `.claude/product/.define-state.json` — populated by steps 01-03.
- `skills/_shared/templates/docs-defaults/prd-global.md` — global PRD template.
- `skills/_shared/templates/docs-defaults/prd-feature.md` — per-feature PRD template.

## Tasks

### A. Load templates

```bash
PLUGIN_ROOT=$(bash skills/_shared/load-config.sh --project-root="$PWD" \
  --field plugin_root)  # falls back to ${ARTYSAN_PLUGIN_ROOT:-$(dirname …)}
TPL_GLOBAL="${PLUGIN_ROOT}/skills/_shared/templates/docs-defaults/prd-global.md"
TPL_FEATURE="${PLUGIN_ROOT}/skills/_shared/templates/docs-defaults/prd-feature.md"
```

### B. Render `prd-global.md`

1. Read `.claude/product/.define-state.json`.
2. Substitute scalars: `{{product_name}}`, `{{vision}}`, `{{north_star_metric}}`,
   `{{north_star_current}}`, `{{north_star_target}}`, `{{target_horizon}}`,
   `{{updated_at}}` (now in ISO-8601, UTC).
3. Expand `{{#personas}}…{{/personas}}` block once per persona.
4. Expand `{{#features}}…{{/features}}` block once per feature.
5. Expand `{{#glossary_terms}}` and `{{#decisions}}` (empty in greenfield — emit
   placeholder rows like `_(none yet)_`).
6. Write to `.claude/product/prd-global.md` (overwrite if exists — extension mode
   merges sections; see merge protocol below).

#### Merge protocol (extension mode)

If `prd-global.md` already exists, do NOT overwrite. Instead:
- Diff sections by H2 heading.
- Replace `## Features` table with the new combined list (existing + new).
- Append new personas (do not deduplicate by name — let user clean up).
- Leave Vision and North Star unchanged unless user explicitly opted to update them
  in step-01.

### C. Render per-feature PRDs

For each feature in `.define-state.json.features`:

1. Create `.claude/product/features/{feature_id}/` (idempotent).
2. Render `{TPL_FEATURE}` with feature-scoped vars:
   `{{feature_id}}`, `{{feature_title}}`, `{{feature_status}}`, `{{owner}}`
   (default to `<TBD>`), `{{target_release}}` (default to `<TBD>`),
   `{{problem_statement}}`, `{{solution_overview}}`, `{{in_scope}}`,
   `{{out_of_scope}}`, `{{user_flow}}` (default `<TBD — fill in /ticket>`),
   `{{updated_at}}`.
3. Expand `{{#acceptance_criteria}}…{{/acceptance_criteria}}`.
4. Expand `{{#user_segments}}`, `{{#edge_cases}}`, `{{#error_states}}`, `{{#wireframes}}`,
   `{{#tickets}}`, `{{#open_questions}}` — emit a single placeholder line if the
   list is empty: `<TBD — fill in next phase>`.
5. Write `prd-feature.md` to the feature directory.

### D. Render meta.json

For each feature, write `.claude/product/features/{feature_id}/meta.json`:

```json
{
  "feature_id": "01-auth",
  "feature_name": "Sign-up with email",
  "state": "defined",
  "priority": "must",
  "created_at": "<ISO-8601>",
  "updated_at": "<ISO-8601>",
  "lang": "<lang>",
  "green_field": <bool from step-00>
}
```

Validate against `skills/_shared/schemas/meta.schema.json`:
```bash
ajv validate -s skills/_shared/schemas/meta.schema.json \
  -d ".claude/product/features/${fid}/meta.json" --spec=draft2020 --strict=false
```

If validation fails, emit the ajv error verbatim and stop. Do NOT advance to step-05.

### E. Progress

```bash
bash skills/_shared/update-progress.sh \
  --project-root="$PWD" \
  --feature-id=_global \
  --step-num=04 \
  --step-name=render \
  --status=ok \
  --skill=define
```

## Acceptance check

- `.claude/product/prd-global.md` exists and contains every feature title from
  `.define-state.json`.
- Every feature has its `prd-feature.md` and `meta.json`.
- Every `meta.json` validates against `meta.schema.json`.

## Next step

→ `step-05-publish.md`
