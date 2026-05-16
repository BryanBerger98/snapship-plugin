# Templates

The plugin resolves templates via `_shared/resolve-template.sh`, which returns
a JSON object `{path, source, render_mode}`. Three sources, in priority order:

1. **Config override** — explicit path in `snap.config.json` →
   `templates.*`. `render_mode=mustache`.
2. **Repo-native** — host markdown template under `.github`/`.gitlab`
   (`ISSUE_TEMPLATE`, `PULL_REQUEST_TEMPLATE`, `issue_templates`,
   `merge_request_templates`). Detected by `_shared/detect-repo-templates.sh`,
   enabled by `templates.use_repo_native` (default `true`). Applies only to
   `ticket` and `pr`; JIRA has no repo-native convention.
   `render_mode=scaffold`.
3. **Bundled** — default template under `_shared/templates/`.
   `render_mode=mustache`.

`render_mode` tells the skill how to fill the template:

- **`mustache`** → variable rendering via `_shared/render-template.sh`
  (`{{var}}` placeholders substituted from JSON context).
- **`scaffold`** → the file is a static markdown skeleton (no placeholders).
  The skill strips the optional YAML frontmatter, keeps the team's section /
  checklist order, and fills each section from the ticket/PR context. Goal:
  match the repo's house style.

## Catalog

| Kind | Type | Platform | Bundled |
|------|------|-----------|--------|
| `ticket` | `user-story` | `github\|gitlab\|jira` | `_shared/templates/tickets/user-story/{platform}.md` |
| `ticket` | `bug` | `github\|gitlab\|jira` | `_shared/templates/tickets/bug/{platform}.md` |
| `ticket` | `epic` | `github\|gitlab\|jira` | `_shared/templates/tickets/epic/{platform}.md` |
| `pr` | — | `github\|gitlab\|default` | `_shared/templates/pr/{platform}.md` |
| `review-thread` | — | `github\|gitlab\|jira` | `_shared/templates/review-thread/{platform}.md` |
| `aggregated-feedback` | — | (no platform) | `_shared/templates/aggregated-feedback.md` |
| `docs-defaults/prd-feature` | — | (standard markdown) | `_shared/templates/docs-defaults/prd-feature.md` |
| `docs-defaults/wireframes-gallery` | — | (standard markdown) | `_shared/templates/docs-defaults/wireframes-gallery.md` |

The "global PRD" is represented by domain pages generated idempotently by
`/snap:doc-import` or `/snap:define` (publish step).

## Repo-native templates (`.github` / `.gitlab`)

When `templates.use_repo_native` is `true` (default), `/ticket` and `/develop`
reuse markdown templates already present in the repo before falling back to
the bundled one. Scanned conventions (`detect-repo-templates.sh`):

| Kind | Platform | Locations |
|------|-----------|--------------|
| `ticket` | `github` | `.github/ISSUE_TEMPLATE/*.md`, `.github/ISSUE_TEMPLATE.md` |
| `ticket` | `gitlab` | `.gitlab/issue_templates/*.md` |
| `ticket` | `jira` | — (no repo-native convention) |
| `pr` | `github` | `.github/PULL_REQUEST_TEMPLATE.md` (+ root, `docs/`, directory form) |
| `pr` | `gitlab` | `.gitlab/merge_request_templates/*.md` |

Rules:

- **Markdown only** — YAML issue forms (`.yml`/`.yaml`) are ignored (the plugin
  doesn't parse form schemas).
- **Name → type mapping**: name containing `bug`/`defect` → `bug`, `epic` →
  `epic`, `story`/`feature` → `user-story`. No match → falls back to the
  single-file form (GitHub) or bundled.
- **PR directory form** → prefers a file named `default.md`, otherwise the
  first one in alphabetical order.
- `review-thread` and `aggregated-feedback` are internal snap artifacts: no
  repo-native convention, they stay on config override or bundled.
- `use_repo_native: false` → repo-native layer is fully ignored.

## User override

`templates` section in `snap.config.json` (all fields optional, default
`null`):

```json
{
  "templates": {
    "use_repo_native": true,
    "tickets": {
      "user_story": ".claude/templates/my-user-story.md",
      "bug":         null,
      "epic":        null
    },
    "pr":                 ".claude/templates/my-pr.md",
    "review_thread":      null,
    "aggregated_feedback": null
  }
}
```

Rules:

- **Relative path** → resolved from project root.
- **Absolute path** (`/...`) → used as-is.
- **Override missing or `null`** → repo-native layer, then bundled fallback.
- **Override pointing to a non-existent file** → `resolve-template.sh` exit 2
  (explicit failure, no silent fallback).
- **An explicit override always wins** over the repo-native template.

PR / review-thread / aggregated-feedback overrides are **unique** (no
per-platform matrix). For tickets, the override is per **type**; the type is
classified automatically by `/ticket` step-03 (bug / epic / user-story by
default), and the platform is derived from `tickets.platform` (the
per-platform bundled file remains the fallback when no override is set).

## Available variables

### Tickets — common

`ticket_id`, `title`, `summary`, `story_id`, `feature_title`, `epic_ref`,
`related_refs`, `labels`, `confidence`, `size`, enrichment context
(`context.codebase`, `context.docs`, `context.web[]`).

### Tickets — `user-story`

`user_persona`, `user_goal`, `user_outcome`, `acceptance_criteria[]`,
`in_scope`, `out_of_scope`, `wireframes[]`, `technical_notes`, `test_unit`,
`test_integration`, `test_e2e`.

### Tickets — `bug`

`repro_steps[]`, `expected_behavior`, `actual_behavior`,
`environment_version`, `environment_runtime`, `environment_user_context`,
`acceptance_criteria[]`, `root_cause`, `regression_surfaces`,
`regression_tests`, `severity`, `frequency`, `first_seen`.

### Tickets — `epic`

`goal`, `success_metrics[]`, `in_scope`, `out_of_scope`, `child_stories[]`,
`acceptance_criteria[]`, `dependencies[]`, `risks[]`, `target_release`,
`epic_size`, `domain_pages`.

### PR

`story_id`, `feature_title`, `branch`, `tickets[]` (list of pushed tickets),
`summary`, `test_plan`, `breaking_changes`, `linked_prs[]`.

### Review thread (comment posted on PR/MR/JIRA ticket)

`overall_severity`, `cycles_used`, `verdict`, `reviewers[]` (technical /
functional / security with `severity`, `severity_threshold`, `blocking`,
`findings[]`), `cross_cutting`, `suggested_fix_order[]`.

### Aggregated feedback (internal, injected into dev for fix-loop)

Same variables as `review-thread`, formatted for dev agent consumption
(no heavy styled markdown, focus on actionable findings).

## Format-specific tweaks

- **GitHub**: `<details>` blocks for context (readable issue), labels via body
  (mapped directly by `tickets-adapter.sh`).
- **GitLab**: inline `/label` quick actions (portable, no platform-specific
  CLI flag).
- **JIRA**: wiki-markup, AC under `*Acceptance criteria*` for native filters.

## Initial push of docs templates

`docs-defaults/*.md` templates pushed via `docs-adapter.sh apply-template` on
first setup, then applied at each page creation.

## Additional templates (other uses)

- `_shared/templates/session-start-hook.sh.tpl` — opt-in SessionStart hook
  (copied user-side).
