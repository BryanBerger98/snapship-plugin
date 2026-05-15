## Epic summary

{{summary}}

## Goal

{{goal}}

## Success metrics

{{#success_metrics}}
- **{{metric_name}}** — {{metric_target}}
{{/success_metrics}}

## In scope

{{in_scope}}

## Out of scope

{{out_of_scope}}

## Child stories

{{#child_stories}}
- [ ] {{child_ref}} — {{child_title}}
{{/child_stories}}

## Acceptance criteria (epic-level)

{{#acceptance_criteria}}
- [ ] **AC-{{ac_id}}** {{ac_text}}
{{/acceptance_criteria}}

## Dependencies

{{#dependencies}}
- {{dep_ref}} — {{dep_note}}
{{/dependencies}}

## Risks

{{#risks}}
- **{{risk_label}}** — {{risk_mitigation}}
{{/risks}}

## Timeline

- **Target release:** {{target_release}}
- **Estimated size:** {{epic_size}}  <!-- s | m | l | xl -->

## References

- Feature PRD: `.snap/PRDs/{{feature_id}}.md`
- Domain pages: {{domain_pages}}
- Related: {{related_refs}}

/label ~"feature::{{feature_id}}" ~"type::epic" ~"size::{{epic_size}}"
/milestone {{milestone}}
/assign {{assignee}}

<!--
Variables: identical to github.md plus:
  {{milestone}}               string
  {{assignee}}                string
-->
