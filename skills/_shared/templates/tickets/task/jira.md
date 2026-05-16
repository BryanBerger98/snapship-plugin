h2. Summary

{{summary}}

h2. Scope hints

{{#scope_hints}}
* {{.}}
{{/scope_hints}}

h2. Acceptance criteria

{{#acceptance_criteria}}
* (/) *AC-{{ac_id}}* {{ac_text}}
{{/acceptance_criteria}}

h2. Technical notes

{{technical_notes}}

h2. Test hints

* (/) {{test_unit}}
* (/) {{test_integration}}

h2. References

* Feature PRD: {{feature_prd_link}}
* Parent story: {{parent_ref}}
* Related: {{related_refs}}

----
snap-feature: {{story_id}}
snap-platform: jira
snap-template-version: 1
{{!--
Jira wiki-style markup (h2., *bold*, (/) checked, lists with leading *).
Trailing ---- block carries machine-readable snap metadata scrubbed on
round-trip parse.

Variables:
  {{summary}}                 paragraph (Jira wiki markup)
  {{scope_hints}}             list of strings
  {{acceptance_criteria}}     list — {ac_id, ac_text}
  {{technical_notes}}         paragraph
  {{test_unit}}               string
  {{test_integration}}        string
  {{story_id}}                string
  {{feature_prd_link}}        URL or "—"
  {{parent_ref}}              Jira key or "—"
  {{related_refs}}            comma-separated keys
--}}
