---
step: 04-format
next_step: 05-push
description: Render each story via the resolved ticket template (per type + platform) to produce the final body.
---

# step-04 — format

Convert each structured story JSON into a platform-native body. The template is
resolved per story by type + platform via `_shared/resolve-template.sh`:
explicit config override > repo-native (`.github`/`.gitlab`) > bundled default.

## Tasks

1. **Resolve template per story** based on `story.type` (set in step-03) and
   `platform`:
   ```bash
   tpl_json=$(bash skills/_shared/resolve-template.sh \
     --kind=ticket \
     --type="$story_type" \
     --platform="$platform" \
     --project-root="$PWD")
   tpl=$(printf '%s' "$tpl_json" | jq -r '.path')
   render_mode=$(printf '%s' "$tpl_json" | jq -r '.render_mode')
   ```
   `story_type ∈ {user-story, bug, epic}` (defaulted to `user-story` in step-03).
   The resolver returns JSON `{path, source, render_mode}`:
   - `source=config` → `templates.tickets.<type>` override in `snap.config.json`.
   - `source=repo-native` → a host issue template under `.github/ISSUE_TEMPLATE/`
     or `.gitlab/issue_templates/` (filename matched to the ticket type). Gated
     by `templates.use_repo_native` (default true); JIRA has no repo-native
     convention so it never resolves to one.
   - `source=bundled` → the bundled `tickets/${type}/${platform}.md`.

2. **Render per story** — branch on `render_mode`:

   - **`render_mode=mustache`** (config override or bundled): render with
     `_shared/render-template.sh` against `$tpl`. Variables differ per type:

     - **user-story** (existing): `ticket_id, title, summary, user_persona,
       user_goal, user_outcome, acceptance_criteria[], in_scope, out_of_scope,
       wireframes[], technical_notes, test_unit, test_integration, test_e2e,
       size, confidence, feature_id, epic_ref, related_refs`. Plus enriched
       `context.codebase`, `context.docs`, `context.web[]`.
     - **bug**: `summary, repro_steps[], expected_behavior, actual_behavior,
       environment_version, environment_runtime, environment_user_context,
       acceptance_criteria[], root_cause, regression_surfaces, regression_tests,
       severity, frequency, feature_id, first_seen, related_refs`.
     - **epic**: `summary, goal, success_metrics[], in_scope, out_of_scope,
       child_stories[], acceptance_criteria[], dependencies[], risks[],
       target_release, epic_size, feature_id, domain_pages, related_refs`.

     The enrichment agent (step-03) populates type-specific fields when `type`
     is set; missing fields render empty (template comment blocks document them).

   - **`render_mode=scaffold`** (repo-native): the file is a static markdown
     scaffold, not a mustache template. Read `$tpl`, **strip the YAML
     frontmatter** (the leading `---` … `---` block GitHub issue templates carry
     — `name:`, `about:`, `labels:`, …; it is editor metadata, not body
     content), then fill each section in place from the structured story JSON +
     enriched context. Keep the repo's heading order and any checklists; do not
     re-impose the bundled layout — the point is to match the team's house
     style. Drop placeholder/comment prose, leave a section empty rather than
     inventing content. The result is `body_rendered`.

3. **Inject the docs link**: read `.snap/manifests/${feature_id}.manifest.json`
   for `.refs.prd.url` (absent if `documentation.platform=none`); render it
   into the ticket body header (`Spec : <url>`).

4. **Format-specific tweaks**:
   - **GitHub**: use `<details>` blocks for context to keep the issue readable; map
     `labels` 1:1.
   - **GitLab**: add `/label` quick actions inline; do not add labels via CLI flag
     (use the body for portability).
   - **JIRA**: use the wiki-markup template; include the AC in `*Acceptance criteria*`
     section so the JIRA-side filter works.

5. **Validate body** is non-empty and ≤ platform max (GitHub 65k, GitLab 1M, JIRA 32k
   per field). Truncate `context.web` first if needed; never truncate AC.

6. **Update draft file** with `body_rendered` per story.

7. **Append progress**:
   ```bash
   bash skills/_shared/progress.sh step \
     --project-root="$PWD" \
     --skill=ticket \
     --feature-id="$feature_id" \
     --step-num=04 \
     --step-name=format \
     --status=ok
   ```

## Acceptance check

- Every story has `body_rendered` (non-empty, ≤ platform limit).

## Next step

→ `step-05-push.md`
