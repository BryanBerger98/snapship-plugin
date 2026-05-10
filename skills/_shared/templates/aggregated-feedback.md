# Aggregated review feedback — cycle {{cycle}}

Internal blob consumed by the dev agent during `/develop` Phase 2 fix loop.
Structured so the agent can locate findings and plan minimal patches.

> Verdict: **{{verdict}}** · Max severity: `{{max_severity}}` · Cycle {{cycle}}/{{cycles_max}}

## Per-reviewer severities

| Reviewer | Severity | Threshold | Blocking |
|----------|----------|-----------|----------|
| Technical | `{{review_technical_severity}}` | `{{review_technical_threshold}}` | {{review_technical_blocking}} |
| Functional | `{{review_functional_severity}}` | `{{review_functional_threshold}}` | {{review_functional_blocking}} |
| Security | `{{review_security_severity}}` | `{{review_security_threshold}}` | {{review_security_blocking}} |

## Findings (grouped by file)

{{#files}}
### `{{file_path}}`

{{#file_findings}}
- **[{{finding_reviewer}} · {{finding_severity}}]** {{finding_title}}
{{#finding_line}}  Line: `{{finding_line}}`{{/finding_line}}

  {{finding_body}}

{{#finding_suggestion}}
  ```
  {{finding_suggestion}}
  ```
{{/finding_suggestion}}

{{/file_findings}}
{{/files}}

## Cross-cutting recommendations

{{#cross_cutting}}
- **{{cc_label}}** — {{cc_body}}
{{/cross_cutting}}

## Suggested fix order

{{#fix_order}}
{{fix_step}}. {{fix_description}}
{{/fix_order}}

---

<!--
Variables:
  {{cycle}}                          integer
  {{cycles_max}}                     integer
  {{verdict}}                        enum — pass|fix-required|blocked
  {{max_severity}}                   enum — none|info|minor|major|critical
  {{review_technical_severity}}      enum
  {{review_technical_threshold}}     enum (config develop.reviews.technical.severity_threshold)
  {{review_technical_blocking}}      bool — severity >= threshold
  ... (same for functional, security)
  {{files}}                          list — {file_path, file_findings: [...]}
  {{file_findings}}                  list — {finding_reviewer, finding_severity,
                                              finding_title, finding_line?,
                                              finding_body, finding_suggestion?}
  {{cross_cutting}}                  list — {cc_label, cc_body}
                                     (architectural/repeated patterns spanning files)
  {{fix_order}}                      list — {fix_step, fix_description}
                                     (prioritized: blocking first, then by severity)
-->
