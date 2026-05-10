## Summary

{{summary}}

## Steps to reproduce

{{#repro_steps}}
1. {{.}}
{{/repro_steps}}

## Expected behavior

{{expected_behavior}}

## Actual behavior

{{actual_behavior}}

## Environment

- **Version / commit:** {{environment_version}}
- **Browser / OS / runtime:** {{environment_runtime}}
- **User context:** {{environment_user_context}}

## Acceptance criteria

{{#acceptance_criteria}}
- [ ] **AC-{{ac_id}}** {{ac_text}}
{{/acceptance_criteria}}

## Root cause hypothesis

{{root_cause}}

## Regression risk

- **Affected surfaces:** {{regression_surfaces}}
- **Tests to add:** {{regression_tests}}

## Severity

- **Severity:** {{severity}}  <!-- low | medium | high | critical -->
- **Frequency:** {{frequency}}  <!-- rare | sometimes | always -->

## References

- Feature PRD: `.claude/product/features/{{feature_id}}/prd-feature.md`
- First seen: {{first_seen}}
- Related: {{related_refs}}

/label ~"feature::{{feature_id}}" ~"type::bug" ~"severity::{{severity}}"
/milestone {{milestone}}
/assign {{assignee}}

<!--
Variables: identical to github.md plus:
  {{milestone}}               string — milestone title (use "" to omit)
  {{assignee}}                string — @username (use "" to omit)
-->
