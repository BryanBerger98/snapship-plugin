---
step: 04-render
next_step: 05-publish
description: Render per-feature PRDs (change-request format) from templates using cached state. Materialize manifests/{slug}.manifest.json. v1.0 — no prd-global, no meta.json.
---

# step-04 — render

Materialize the markdown PRD per feature from cached state + bundled template,
and bootstrap the per-feature manifest under `.snap/manifests/`.

The v0.1 `prd-global.md` artefact is **dropped**. The "global PRD" concept is
replaced by domain pages on the doc platform (created/idempotent in step-05).

The v0.2 `meta.json` is **dropped** in v1.0 — replaced by
`.snap/manifests/{story_id}.manifest.json` (schema_version, refs, sync_state).

## Inputs

- `.snap/.define-state.json` — populated by steps 01-03.
- `skills/_shared/templates/docs-defaults/prd-feature.md` — per-feature PRD template.
- `CONFIG_JSON` — resolved config captured in step-00 (read via `jq -r ... <<<"$CONFIG_JSON"`).

## Tasks

### A. Load template

Templates ship inside the plugin directory. Resolve `PLUGIN_ROOT` from the
script invocation (the plugin sets `SNAP_PLUGIN_ROOT` in its env).

```bash
TPL_FEATURE="${SNAP_PLUGIN_ROOT}/skills/_shared/templates/docs-defaults/prd-feature.md"
```

### B. Render per-feature PRDs

For each feature in `.snap/.define-state.json.features`:

1. **Compute staging path** :
   ```bash
   PRD_STAGING=$(bash skills/_shared/sync-push.sh staging-path \
     --story-id="$fid" --kind=prd \
     --project-root="$PWD")
   # → ${PWD}/.snap/PRDs/${fid}.md
   ```

2. Render `$TPL_FEATURE` with feature-scoped vars (template reflects "change
   request" semantics : forward-looking, archived post-ship, never edited after
   publish) :
   `{{story_id}}`, `{{feature_title}}`, `{{feature_status}}`, `{{owner}}`
   (default `<TBD>`), `{{target_release}}` (default `<TBD>`),
   `{{problem_statement}}`, `{{solution_overview}}`, `{{in_scope}}`,
   `{{out_of_scope}}`, `{{user_flow}}` (default `<TBD — fill in /snap:ticket>`),
   `{{updated_at}}`.

3. Expand `{{#acceptance_criteria}}…{{/acceptance_criteria}}`.

4. Expand `{{#user_segments}}`, `{{#edge_cases}}`, `{{#error_states}}`,
   `{{#wireframes}}`, `{{#tickets}}`, `{{#open_questions}}` — emit a single
   placeholder line if the list is empty: `<TBD — fill in next phase>`.

5. Write the rendered markdown to `$PRD_STAGING` (one file per feature, no
   feature subdir — flat `.snap/PRDs/{slug}.md`).

### C. Bootstrap manifest

For each feature, materialize the manifest via `setup-snap-dir.sh` (idempotent
— leaves existing manifests intact) :

```bash
bash skills/_shared/setup-snap-dir.sh \
  --project-root="$PWD" \
  --story-id="$fid" \
  --story-name="$ftitle" \
  --lang="$lang" \
  --green-field="$has_codebase_inverted"
```

Then patch the optional fields collected in step-03 (priority, domains,
impacted_journeys) :

```bash
MANIFEST=".snap/manifests/${fid}.manifest.json"
DOMAINS_JSON=$(jq -c --arg fid "$fid" \
  '.features[] | select(.story_id == $fid) | .domains' \
  .snap/.define-state.json)
JOURNEYS_JSON=$(jq -c --arg fid "$fid" \
  '.features[] | select(.story_id == $fid)
   | .impacted_journeys
   | map({domain: .domain, journey_slug: .journey_slug})' \
  .snap/.define-state.json)
PRIORITY=$(jq -r --arg fid "$fid" \
  '.features[] | select(.story_id == $fid) | .priority' \
  .snap/.define-state.json)
PARENT_EPIC_ID=$(jq -r --arg fid "$fid" \
  '.features[] | select(.story_id == $fid) | .parent_epic_id // ""' \
  .snap/.define-state.json)
PARENT_EPIC_TITLE=$(jq -r --arg fid "$fid" \
  '.features[] | select(.story_id == $fid) | .parent_epic_title // ""' \
  .snap/.define-state.json)
PARENT_EPIC_PENDING=$(jq -r --arg fid "$fid" \
  '.features[] | select(.story_id == $fid) | .parent_epic_pending // false' \
  .snap/.define-state.json)
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

tmp=$(mktemp)
jq --arg prio "$PRIORITY" \
   --argjson domains "$DOMAINS_JSON" \
   --argjson journeys "$JOURNEYS_JSON" \
   --arg pepic "$PARENT_EPIC_ID" \
   --arg petitle "$PARENT_EPIC_TITLE" \
   --argjson ppending "$PARENT_EPIC_PENDING" \
   --arg ts "$NOW" '
  .priority = $prio
  | .domains = $domains
  | .impacted_journeys = $journeys
  | (if $pepic != "" then .parent_epic_id = $pepic else . end)
  | (if $petitle != "" then .parent_epic_title = $petitle else . end)
  | (if $ppending == true then .parent_epic_pending = true else . end)
  | .updated_at = $ts
' "$MANIFEST" > "$tmp" && mv "$tmp" "$MANIFEST"
```

The `refs` object stays `{}` until step-05 pushes the PRD and acks via
`sync-push.sh ack`.

### D. Validate manifest against schema

```bash
ajv validate \
  -s skills/_shared/schemas/manifest.schema.json \
  -d ".snap/manifests/${fid}.manifest.json" \
  --spec=draft2020 --strict=false
```

On failure, emit the ajv error verbatim and stop. Do NOT advance to step-05.

### E. Progress

```bash
bash skills/_shared/progress.sh step \
  --project-root="$PWD" \
  --skill=define \
  --story-id=_global \
  --step-num=04 \
  --step-name=render \
  --status=ok
```

## Acceptance check

- Every feature has its `.snap/PRDs/{fid}.md` staging file.
- Every feature has its `.snap/manifests/{fid}.manifest.json` with
  `schema_version`, `story_id`, `story_name`, `state="defined"`,
  `priority`, `domains[]`, `impacted_journeys[]`, `refs={}`.
- Every manifest validates against `manifest.schema.json`.
- No `prd-global.md` written (v0.1 artefact dropped).
- No `meta.json` written (v0.2 artefact dropped — v1.0 uses manifest).

## Next step

→ `step-05-publish.md`
