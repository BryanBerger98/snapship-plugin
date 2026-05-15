## Summary

{{summary}}

## User story

As a **{{user_persona}}**, I want **{{user_goal}}** so that **{{user_outcome}}**.

## Acceptance criteria

{{#acceptance_criteria}}
- [ ] **AC-{{ac_id}}** {{ac_text}}
{{/acceptance_criteria}}

## In scope

{{in_scope}}

## Out of scope

{{out_of_scope}}

## Wireframes

{{#wireframes}}
- `{{wireframe_id}}` — `{{wireframe_path}}`
{{/wireframes}}

## Technical notes

{{technical_notes}}

## Test plan

- [ ] {{test_unit}}
- [ ] {{test_integration}}
- [ ] {{test_e2e}}

## Estimation

- **Size:** {{size}}  <!-- xs (≤30min) | s (≤2h) | m (≤1d) | l (>1d, split before merging) -->
- **Confidence:** {{confidence}}  <!-- high | medium | low -->

## References

- Feature PRD: `.snap/PRDs/{{feature_id}}.md`
- Parent epic: {{epic_ref}}
- Related: {{related_refs}}

/label ~"feature::{{feature_id}}" ~"size::{{size}}" ~"type::story"
/milestone {{milestone}}
/assign {{assignee}}

<!--
GitLab quick-actions are emitted as `/label ~"…"`, `/milestone …`, `/assign …`
on their own lines. The platform parses them when the issue is created.

Variables:
  {{summary}}                 paragraph
  {{user_persona}}            string
  {{user_goal}}               string
  {{user_outcome}}            string
  {{acceptance_criteria}}     list — {ac_id, ac_text}
  {{in_scope}}                paragraph
  {{out_of_scope}}            paragraph
  {{wireframes}}              list — {wireframe_id, wireframe_path}
  {{technical_notes}}         paragraph (markdown)
  {{test_unit}}               string
  {{test_integration}}        string
  {{test_e2e}}                string
  {{size}}                    enum — xs|s|m|l
  {{confidence}}              enum — high|medium|low
  {{feature_id}}              string
  {{epic_ref}}                string — glab issue ref or "—"
  {{related_refs}}            string — comma-separated refs
  {{milestone}}               string — milestone title (use "" to omit)
  {{assignee}}                string — @username (use "" to omit)
-->
