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

- Feature PRD: `.claude/product/features/{{feature_id}}/prd-feature.md`
- Domain pages: {{domain_pages}}
- Related: {{related_refs}}

<!--
Variables:
  {{summary}}                 paragraph
  {{goal}}                    paragraph — outcome statement
  {{success_metrics}}         list — {metric_name, metric_target}
  {{in_scope}}                paragraph
  {{out_of_scope}}            paragraph
  {{child_stories}}           list — {child_ref, child_title}
  {{acceptance_criteria}}     list — {ac_id, ac_text}
  {{dependencies}}            list — {dep_ref, dep_note}
  {{risks}}                   list — {risk_label, risk_mitigation}
  {{target_release}}          string
  {{epic_size}}               enum — s|m|l|xl
  {{feature_id}}              string
  {{domain_pages}}            string — comma-separated AFFiNE/Notion URLs
  {{related_refs}}            comma-separated refs
-->
