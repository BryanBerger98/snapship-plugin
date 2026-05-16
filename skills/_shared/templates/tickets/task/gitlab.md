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

/label ~"feature::{{story_id}}" ~"type::task"
/milestone {{milestone}}
/assign {{assignee}}

<!--
GitLab quick-actions are emitted as `/label ~"…"`, `/milestone …`, `/assign …`
on their own lines. Platform parses them on issue creation.

Variables:
  {{summary}}                 paragraph
  {{scope_hints}}             list of strings
  {{acceptance_criteria}}     list — {ac_id, ac_text}
  {{technical_notes}}         paragraph (markdown)
  {{test_unit}}               string
  {{test_integration}}        string
  {{story_id}}                string
  {{parent_ref}}              string
  {{related_refs}}            comma-separated refs
  {{milestone}}               string — "" to omit
  {{assignee}}                string — @username, "" to omit
-->
