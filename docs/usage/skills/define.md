# `/snap:define` — product definition

Builds the PRDs (global, then per feature) from a vision, personas, and a
feature list. Runs a guided questionnaire via `AskUserQuestion`, then
publishes the result to AFFiNE / Notion.

## What it does

Establish or extend the product definition **before any ticket**. The skill
distinguishes two paths:

- **Greenfield**: no PRD yet → full questionnaire (vision → personas
  → features).
- **Extension**: `.snap/` already holds features → add one or more new
  features.

## When to use it

- Right after `/snap:init` on a new project.
- On an existing project to scope a new feature.
- To resume after an interruption (`--resume`).

## Prerequisites

`/snap:init` run once. The skill exits immediately if
`snap.config.json` is missing.

## Syntax

```
/snap:define [--resume|-r] [--lang=fr|en] [--feature=NN-slug]
```

## Flags

| Flag                  | Effect                                                                                                      |
| --------------------- | ----------------------------------------------------------------------------------------------------------- |
| `--resume` / `-r`     | Resumes at the last successful step recorded in `progress.json`. Partial-match on `story_id` (`01` → `01-auth`). With no run in progress, restarts at step-00. |
| `--lang=fr\|en`       | Forces the PRD language (default: detected from an existing PRD, otherwise prompted).                       |
| `--feature=NN-slug`   | Skips the greenfield path, jumps straight to the PRD of an existing feature.                                |

## Pipeline

| #  | Step                  | Role                                                                       |
| -- | --------------------- | -------------------------------------------------------------------------- |
| 00 | `step-00-init.md`     | Parses args, requires `snap.config.json`, detects the codebase, branches greenfield vs extension. |
| 01 | `step-01-vision.md`   | Asks about the vision and north-star metric.                               |
| 02 | `step-02-personas.md` | Asks about 1 to N personas.                                                |
| 03 | `step-03-features.md` | Asks for the feature list with priorities.                                 |
| 04 | `step-04-render.md`   | Generates per-feature PRDs (change-request format) from the templates.     |
| 05 | `step-05-publish.md`  | Archives PRD pages by date, ensures the domain + journey pages exist.      |

Steps are **idempotent**: re-running a step with the same inputs produces the same output.

## Outputs

- `.snap/manifests/{story_id}/prd-feature.md` — one per feature.
- `.snap/manifests/{story_id}.manifest.json` — `state=defined`,
  `domains[]`, `impacted_journeys[]`, `prd.{page_id,url,path}` after publication.
- `.snap/manifests/_taxonomy.json` — domain + journey page IDs (idempotent).
- `.snap/progress.json` — run journal.
- AFFiNE / Notion:
  - PRD page under `{prd_root}/{YYYY}/{MM-YYYY}/{NN-feature}` (immutable archive).
  - Domain + journey pages under `{functional_root}/{domain}/{journey}` (living spec,
    body filled later by `/snap:doc-update`).

## Next step

`/snap:ticket --feature=NN-slug` to break the feature down into tickets.
