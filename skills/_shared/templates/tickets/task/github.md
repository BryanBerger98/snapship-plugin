## Summary

{{summary}}

## Scope hints

{{#scope_hints}}
- {{.}}
{{/scope_hints}}

## Acceptance criteria

{{#acceptance_criteria}}
- [ ] **AC-{{ac_id}}** {{ac_text}}
{{/acceptance_criteria}}

## Technical notes

{{technical_notes}}

## Test hints

- [ ] {{test_unit}}
- [ ] {{test_integration}}

## References

- Feature PRD: `.snap/PRDs/{{story_id}}.md`
- Parent story: {{parent_ref}}
- Related: {{related_refs}}

<!--
Variables:
  {{summary}}                 paragraph
  {{scope_hints}}             list of strings — concrete files/modules touched
  {{acceptance_criteria}}     list — {ac_id, ac_text}
  {{technical_notes}}         paragraph (markdown)
  {{test_unit}}               string
  {{test_integration}}        string
  {{story_id}}                string
  {{parent_ref}}              string — user-story/epic ref or "—"
  {{related_refs}}            comma-separated refs
-->
