h2. Epic summary

{{summary}}

h2. Goal

{{goal}}

h2. Success metrics

{{#success_metrics}}
* *{{metric_name}}* — {{metric_target}}
{{/success_metrics}}

h2. In scope

{{in_scope}}

h2. Out of scope

{{out_of_scope}}

h2. Child stories

{{#child_stories}}
* (/) {{child_ref}} — {{child_title}}
{{/child_stories}}

h2. Acceptance criteria (epic-level)

{{#acceptance_criteria}}
* (/) *AC-{{ac_id}}* {{ac_text}}
{{/acceptance_criteria}}

h2. Dependencies

{{#dependencies}}
* {{dep_ref}} — {{dep_note}}
{{/dependencies}}

h2. Risks

{{#risks}}
* *{{risk_label}}* — {{risk_mitigation}}
{{/risks}}

h2. Timeline

* *Target release:* {{target_release}}
* *Estimated size:* {{epic_size}}  -- s | m | l | xl

h2. References

* Feature PRD: {{feature_prd_link}}
* Domain pages: {{domain_pages}}
* Related: {{related_refs}}

----
snap-feature: {{feature_id}}
snap-platform: jira
snap-template-version: 1
snap-ticket-type: epic
{{!--
Variables: see github.md plus {{feature_prd_link}}.
--}}
