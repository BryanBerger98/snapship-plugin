---
step: 04-format
next_step: 05-push
description: Render each story via templates/ticket-{platform}.md to produce the final body.
---

# step-04 — format

Convert the structured story JSON into a platform-native body using
`templates/ticket-{github,gitlab,jira}.md`.

## Tasks

1. **Pick the template** based on `platform`:
   ```bash
   tpl="skills/_shared/templates/ticket-${platform}.md"
   [ -f "$tpl" ] || { echo "ERROR: template missing: $tpl" >&2; exit 1; }
   ```

2. **Render per story** using the bundled mustache helper (or the
   `setup-product-dir.sh` rendering routine). Variables exposed:
   ```
   ticket_id, title, ac_text, expected_files (list), depends_on (list),
   labels (list), context.codebase, context.docs, context.web (list),
   feature_id, feature_title, feature_url (AFFiNE/Notion link)
   ```
   Iterate lists with `{{#expected_files}}- {{.}}{{/expected_files}}` etc.

3. **Inject the docs link**: read `.claude/product/.docs-cache.json` for the
   feature's `prd_feature.url` (or `null` if `documentation.platform=none`); render
   it into the ticket body header (`Spec: <url>`).

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
   bash skills/_shared/update-progress.sh \
     --project-root="$PWD" \
     --feature-id="$feature_id" \
     --step-num=04 \
     --step-name=format \
     --status=ok \
     --skill=ticket
   ```

## Acceptance check

- Every story has `body_rendered` (non-empty, ≤ platform limit).

## Next step

→ `step-05-push.md`
