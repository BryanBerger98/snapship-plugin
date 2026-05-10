---
step: 04-render
next_step: 05-publish
description: Render per-feature PRDs (change-request format) from templates using cached state. v0.2 — no prd-global anymore.
---

# step-04 — render (v0.2)

Materialize the markdown PRD per feature from the cached state + bundled template.

The v0.1 `prd-global.md` output is **dropped**. The "global PRD" concept is
replaced by domain pages on the doc platform (created by `/snap:doc-import` or
ensured idempotently by step-05 of `/snap:define`).

## Inputs

- `.claude/product/.define-state.json` — populated by steps 01-03.
- `skills/_shared/templates/docs-defaults/prd-feature.md` — per-feature PRD template.

## Tasks

### A. Load template

```bash
PLUGIN_ROOT=$(bash skills/_shared/load-config.sh --project-root="$PWD" \
  --field plugin_root)  # falls back to ${SNAP_PLUGIN_ROOT:-$(dirname …)}
TPL_FEATURE="${PLUGIN_ROOT}/skills/_shared/templates/docs-defaults/prd-feature.md"
```

### B. Render per-feature PRDs

For each feature in `.define-state.json.features`:

1. Create `.claude/product/features/{feature_id}/` (idempotent).
2. Render `{TPL_FEATURE}` with feature-scoped vars (PRD template should reflect
   "change request" semantics: forward-looking, archived post-ship, never edited
   after publish):
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

The renamed sections C+D below were B+C in v0.1 (global PRD render dropped).

### C. Render meta.json (v0.2)

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
  "green_field": <bool from step-00>,
  "domains": ["auth"],
  "impacted_journeys": [
    {"domain": "auth", "journey_slug": "login-flow"}
  ]
}
```

`domains` and `impacted_journeys` come from `.define-state.json.features[].domains`
+ `impacted_journeys` (collected in step-03 phase B7-B8). Strip the `is_new` and
`journey_title` flags here — they're only needed by the publish step (read from
state file directly there).

The `prd` object is **not** set yet; step-05-publish populates it after the
PRD page is created on AFFiNE/Notion.

Validate against `skills/_shared/schemas/meta.schema.json`:
```bash
ajv validate -s skills/_shared/schemas/meta.schema.json \
  -d ".claude/product/features/${fid}/meta.json" --spec=draft2020 --strict=false
```

If validation fails, emit the ajv error verbatim and stop. Do NOT advance to step-05.

### D. Progress

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

- Every feature has its `prd-feature.md` and `meta.json`.
- Every `meta.json` validates against `meta.schema.json` (v0.2 — `domains[]` +
  `impacted_journeys[]` populated, `prd` object NOT yet set).
- No `prd-global.md` written (v0.1 artefact dropped).

## Next step

→ `step-05-publish.md`
