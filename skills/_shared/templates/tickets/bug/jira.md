h2. Summary

{{summary}}

h2. Steps to reproduce

{{#repro_steps}}
# {{.}}
{{/repro_steps}}

h2. Expected behavior

{{expected_behavior}}

h2. Actual behavior

{{actual_behavior}}

h2. Environment

* *Version / commit:* {{environment_version}}
* *Browser / OS / runtime:* {{environment_runtime}}
* *User context:* {{environment_user_context}}

h2. Acceptance criteria

{{#acceptance_criteria}}
* (/) *AC-{{ac_id}}* {{ac_text}}
{{/acceptance_criteria}}

h2. Root cause hypothesis

{{root_cause}}

h2. Regression risk

* *Affected surfaces:* {{regression_surfaces}}
* *Tests to add:* {{regression_tests}}

h2. Severity

* *Severity:* {{severity}}  -- low | medium | high | critical
* *Frequency:* {{frequency}}  -- rare | sometimes | always

h2. References

* Feature PRD: {{feature_prd_link}}
* First seen: {{first_seen}}
* Related: {{related_refs}}

----
snap-feature: {{feature_id}}
snap-platform: jira
snap-template-version: 1
snap-ticket-type: bug
{{!--
Variables: see github.md plus:
  {{feature_prd_link}}        URL or "—"
--}}
