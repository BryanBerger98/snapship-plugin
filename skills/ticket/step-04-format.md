---
step: 04-format
next_step: 05-push
description: Render each draft via type-specific template, fill `commit_type` + suggested `branch_name`, validate Ajv before persisting to ephemeral cache.
---

# step-04 — format

Convert each draft into a platform-native body + structural metadata
(`commit_type`, `branch_name`) ready for push. Templates differ per
`story_type ∈ {epic, user-story, task, bug}`. Validate every draft against
`tickets.schema.json` **before** writing back to the ephemeral cache —
fail-clean if any draft would break the schema's `allOf` (Epic forbids
`branch_name` / `commit_sha`).

## Inputs

- `.snap/.runtime/<SUBJECT_ID>/drafts.json` — drafts from step-03c carrying
  `story_type`, hierarchy refs, metadata, enrichment context.
- `.snap/manifests/${story_id}.manifest.json` — only in normal mode, for
  `.refs.prd.url` to inject as « Spec : <url> » in the body header.

## Template resolution per draft

Resolve via `_shared/resolve-template.sh` based on `story_type` + platform:

```bash
tpl_json=$(bash skills/_shared/resolve-template.sh \
  --kind=ticket \
  --type="$story_type" \
  --platform="$platform" \
  --project-root="$PWD")
tpl=$(printf '%s' "$tpl_json"          | jq -r '.path')
render_mode=$(printf '%s' "$tpl_json"  | jq -r '.render_mode')
```

Resolution order : `config override` > `repo-native` (`.github/.gitlab`) >
`bundled` (`skills/_shared/templates/tickets/<type>/<platform>.md`). JIRA
has no repo-native convention so it always falls back to bundled or config.

## Render modes

### `render_mode=mustache` (config override or bundled)

Render with `_shared/render-template.sh` against `$tpl`. Variables differ
per `story_type` :

- **epic** : `summary, goal, success_metrics[], in_scope, out_of_scope,
  child_stories[], acceptance_criteria[], dependencies[], risks[],
  target_release, epic_size, story_id, domain_pages, related_refs`.
- **user-story** : `summary, user_persona, user_goal, user_outcome,
  acceptance_criteria[], in_scope, out_of_scope, wireframes[],
  technical_notes, test_unit, test_integration, test_e2e, size, confidence,
  story_id, epic_ref, related_refs`. Plus enriched `context.codebase`,
  `context.docs`, `context.web[]`.
- **task** : `summary, scope_hints[], acceptance_criteria[],
  technical_notes, test_unit, test_integration, story_id, parent_ref,
  related_refs`.
- **bug** : `summary, repro_steps[], expected_behavior, actual_behavior,
  environment_version, environment_runtime, environment_user_context,
  acceptance_criteria[], root_cause, regression_surfaces, regression_tests,
  severity, frequency, story_id, first_seen, related_refs`.

Missing fields render empty — template comment blocks document them.

### `render_mode=scaffold` (repo-native)

The file is a static markdown scaffold, not mustache. Read `$tpl`, **strip
the YAML frontmatter** (the leading `---` … `---` block GitHub/GitLab issue
templates carry — editor metadata, not body content), then fill each
section in place from the draft + enrichment context. Keep the repo's
heading order and any checklists ; do not re-impose the bundled layout —
match team house style. Drop placeholder/comment prose, leave a section
empty rather than inventing content. Result is `body_rendered`.

## `commit_type` default heuristic

For non-Epic drafts, suggest `commit_type` based on `story_type` :

| `story_type` | Default `commit_type` | Notes |
|---|---|---|
| `user-story` | `feat` | New user-facing capability. |
| `bug` | `fix` | Regression / defect repair. |
| `task` | `refactor` if title contains `refactor`/`rework` ; `chore` else | Tech work without user value. |
| `epic` | *(omitted — Epics carry no branch/commit)* | Schema forbids `commit_sha` on epic. |

User overrides remain possible at confirmation prompt. Inline LLM is the
default — plug-in point for `snap-ticket-classifier` subagent in Phase H
(see `.claude/plan/ticket-hierarchy-redesign/02-subagents-design.md`).

The chosen `commit_type` must remain in the enum :
`feat | fix | chore | refactor | docs | test | perf | build | ci`.

## `branch_name` suggestion

For every non-Epic draft, propose a `branch_name` via
`_shared/apply-naming.sh` :

```bash
branch_name=$(bash skills/_shared/apply-naming.sh branch \
  --context="$(jq -n \
    --arg t "$commit_type" \
    --arg id "$local_id" \
    --arg slug "$(printf '%s' "$title" | head -c 40)" \
    '{type:$t, ticket_id:$id, slug:$slug}')")
```

Default pattern : `{commit_type}/{ticket_id}-{slug}` (decision #12 ;
configurable via `naming.branch_pattern`). **Skip the call entirely when
`story_type=epic`** — schema's `allOf` forbids `branch_name` on Epic and
Ajv would reject the draft.

## Docs link injection (normal mode only)

Read `.snap/manifests/${story_id}.manifest.json` for `.refs.prd.url`
(absent if `documentation.platform=none`) ; render as `Spec : <url>` in the
ticket body header. Skip silently under `--standalone` (no manifest).

## Platform tweaks

- **GitHub** : `<details>` blocks for enrichment context to keep issues
  readable ; map `labels` 1:1.
- **GitLab** : `/label`, `/milestone`, `/assign` quick-actions inline ; do
  not pass labels via CLI flag (use the body for portability).
- **JIRA** : wiki-markup template, AC under `*Acceptance criteria*`
  section so the JIRA-side filter works.

## Ajv validation pre-write

For each draft, before persisting, validate the assembled object against
`skills/_shared/schemas/tickets.schema.json` via `ajv-cli` (same path
`load-config.sh` uses) :

```bash
schema=skills/_shared/schemas/tickets.schema.json
tmp=$(mktemp -t snap-ticket-XXXXXX.json)
printf '%s' "$draft_json" > "$tmp"
if command -v ajv >/dev/null 2>&1; then AJV="ajv"
elif command -v npx >/dev/null 2>&1; then AJV="npx -y ajv-cli"
else echo "WARN: ajv-cli unavailable — skipping pre-write validation" >&2; AJV=""; fi
if [ -n "$AJV" ]; then
  $AJV validate --spec=draft2020 -s "$schema" -d "$tmp" --strict=false \
    || { echo "ERROR: draft ${local_id} fails schema" >&2; trash "$tmp"; exit 1; }
fi
trash "$tmp"
```

Hard reject on failure — the only realistic case here is `allOf`
violation : Epic draft accidentally carrying `branch_name` or `commit_sha`.
Surface the offending `local_id` + key, abort the step without writing
the cache.

## Tasks

1. **Read drafts + manifest** from ephemeral cache (and persistent
   manifest if normal mode).

2. **For each draft** :
   - Resolve template (see above).
   - Render `body_rendered` via the matching render-mode branch.
   - Suggest `commit_type` (skip for Epic).
   - Suggest `branch_name` via `apply-naming.sh` (skip for Epic).
   - Inject docs link in normal mode.
   - Validate body non-empty + ≤ platform max (GitHub 65k, GitLab 1M, JIRA
     32k per field). Truncate `context.web` first ; never truncate AC.
   - Ajv-validate the full draft object — abort step on violation.

3. **Persist updated drafts** to
   `.snap/.runtime/<SUBJECT_ID>/drafts.json` via `cache-runtime.sh write`.

4. **Append progress** :
   ```bash
   bash skills/_shared/progress.sh step \
     --project-root="$PWD" \
     --skill=ticket \
     --story-id="$story_id" \
     --step-num=04 \
     --step-name=format \
     --status=ok
   ```

## Failure handling

- Template missing for an exotic platform → fall back to a generic
  markdown render with the canonical sections (`Summary`, `Acceptance
  criteria`, `References`) and warn.
- Ajv violation (Epic with `branch_name`/`commit_sha`) → fail-clean with
  the offending `local_id` + key surfaced.
- Body exceeds platform max → truncate `context.web` first, then
  `context.docs`. Never touch AC or `body_rendered` core sections.

## Acceptance check

- Every draft has `body_rendered` (non-empty, ≤ platform limit).
- Every non-Epic draft has `commit_type` ∈ enum and `branch_name` set.
- Every Epic draft has neither `branch_name` nor `commit_sha`.
- All drafts pass Ajv against `tickets.schema.json`.

## Next step

→ `step-05-push.md`
