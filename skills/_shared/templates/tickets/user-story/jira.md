h2. Summary

{{summary}}

h2. User story

As a *{{user_persona}}*, I want *{{user_goal}}* so that *{{user_outcome}}*.

h2. Acceptance criteria

{{#acceptance_criteria}}
* (/) *AC-{{ac_id}}* {{ac_text}}
{{/acceptance_criteria}}

h2. In scope

{{in_scope}}

h2. Out of scope

{{out_of_scope}}

h2. Wireframes

{{#wireframes}}
* {{wireframe_id}} — {{wireframe_path}}
{{/wireframes}}

h2. Technical notes

{{technical_notes}}

h2. Test plan

* (/) {{test_unit}}
* (/) {{test_integration}}
* (/) {{test_e2e}}

h2. Estimation

* *Size:* {{size}}  -- xs (<=30min) | s (<=2h) | m (<=1d) | l (>1d, split before merging)
* *Confidence:* {{confidence}}  -- high | medium | low
* *Story points:* {{story_points}}

h2. References

* Feature PRD: {{feature_prd_link}}
* Parent epic: {{epic_ref}}
* Related: {{related_refs}}

----
snap-feature: {{story_id}}
snap-platform: jira
snap-template-version: 1
{{!--
Jira uses wiki-style markup (h2., *bold*, (/) for checked, lists with leading *).
The trailing ---- block carries machine-readable snap metadata that the
tickets-adapter scrubs on round-trip parse.

Variables:
  {{summary}}                 paragraph (Jira wiki markup)
  {{user_persona}}            string
  {{user_goal}}               string
  {{user_outcome}}            string
  {{acceptance_criteria}}     list — {ac_id, ac_text}
  {{in_scope}}                paragraph
  {{out_of_scope}}            paragraph
  {{wireframes}}              list — {wireframe_id, wireframe_path}
  {{technical_notes}}         paragraph
  {{test_unit}}               string
  {{test_integration}}        string
  {{test_e2e}}                string
  {{size}}                    enum — xs|s|m|l
  {{confidence}}              enum — high|medium|low
  {{story_points}}            integer
  {{story_id}}              string
  {{feature_prd_link}}        URL or "—"
  {{epic_ref}}                Jira key or "—"
  {{related_refs}}            comma-separated keys
--}}
