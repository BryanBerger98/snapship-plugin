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

- Feature PRD: `.snap/PRDs/{{feature_id}}.md`
- First seen: {{first_seen}}
- Related: {{related_refs}}

<!--
Variables:
  {{summary}}                 paragraph
  {{repro_steps}}             list of strings
  {{expected_behavior}}       paragraph
  {{actual_behavior}}         paragraph
  {{environment_version}}     string
  {{environment_runtime}}     string
  {{environment_user_context}} string
  {{acceptance_criteria}}     list — {ac_id, ac_text}
  {{root_cause}}              paragraph (markdown)
  {{regression_surfaces}}     string
  {{regression_tests}}        string
  {{severity}}                enum — low|medium|high|critical
  {{frequency}}               enum — rare|sometimes|always
  {{feature_id}}              string
  {{first_seen}}              ISO date or commit SHA
  {{related_refs}}            comma-separated refs
-->
