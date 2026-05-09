---
step: 01-load
next_step: 02-decompose
description: Load prd-feature.md and extract AC, scope, edge cases, wireframe refs into context.
---

# step-01 — load

Read the feature PRD and stage its content for decomposition.

## Tasks

1. **Read `prd-feature.md`** for the active `feature_id`. Validate it has the
   sections required by `templates/docs-defaults/prd-feature.md`:
   - Problem
   - Solution overview
   - Acceptance criteria (AC-N format)
   - In scope / Out of scope
   - Wireframe references (optional)

   If a required section is missing, surface a parse error with the section name and
   abort with `progress.md status=fail`.

2. **Extract structured data** into a working JSON kept in context (no file write yet):
   ```json
   {
     "feature_id": "01-auth",
     "feature_title": "...",
     "problem": "...",
     "solution_overview": "...",
     "acceptance_criteria": [
       {"ac_id": "1", "ac_text": "..."}
     ],
     "in_scope": "...",
     "out_of_scope": "...",
     "wireframes": ["screen-id-1", "screen-id-2"]
   }
   ```

   Use `awk` or `sed` to slice between `## ` headings; do not write the JSON to disk.

3. **Read `meta.json`** for the feature; remember `tickets_count` (used to detect
   re-runs) and `affine_page_id` / `notion_page_id` (linked from each ticket body).

4. **Cross-reference wireframes**: if `wireframes-gallery.md` exists at
   `.claude/product/wireframes-gallery.md`, look up each wireframe ID and capture the
   image URL/blob ID for inclusion in the ticket body.

5. **Append progress**:
   ```bash
   bash skills/_shared/update-progress.sh \
     --project-root="$PWD" \
     --feature-id="$feature_id" \
     --step-num=01 \
     --step-name=load \
     --status=ok \
     --skill=ticket
   ```

## Acceptance check

- All required PRD sections parsed without error.
- `acceptance_criteria` array has ≥ 1 entry.

## Next step

→ `step-02-decompose.md`
