# `/snap:doc-update` — refresh the living functional docs

Updates the journey pages impacted by a feature after it ships. Reads the
PRD + current journey content + the feature's git diff, then patches or
rewrites the journey pages via AI.

## What it does

Keep the functional docs **alive** and up to date after shipping.

- The **PRD** page (`Change Requests/{YYYY}/{MM-YYYY}/`) is **never
  modified** — immutable archive of intent.
- The **journey** pages (`Product Docs/{domain}/{journey}/`) are the
  living spec — this skill keeps them current.

## When to use it

| Source                  | Condition                                                                       |
| ----------------------- | ------------------------------------------------------------------------------- |
| Auto post-`/snap:qa`    | `documentation.auto_update_on_qa_success: true` AND the feature reaches `qa-validated`. |
| Manual                  | `/snap:doc-update --feature=NN-slug`.                                           |

## Prerequisites

- `/snap:init` run (`snap.config.json` exists).
- `documentation.platform ∈ {affine, notion}` (skipped if `none`).
- MCP for that platform reachable.
- The feature has a `manifest.json` with `state == "qa-validated"` and `prd.page_id`
  set.
- Every `impacted_journeys[]` entry has a matching entry in
  `_taxonomy.json`.

## Syntax

```
/snap:doc-update --feature=NN-slug [--mode=diff|rewrite] [--dry-run] [-a]
```

## Flags

| Flag                  | Effect                                                                           |
| --------------------- | -------------------------------------------------------------------------------- |
| `--feature=NN-slug`   | **Required.** Partial-match on `feature_id` (e.g. `01` → `01-auth`).             |
| `--mode=diff\|rewrite`| Overrides `documentation.auto_update_mode`. `diff` = AI patch, `rewrite` = full rewrite. |
| `--dry-run`           | Renders the proposed updates locally, does not push to AFFiNE / Notion.          |
| `-a` / `--auto`       | Skips confirmations (used by the post-QA hook).                                  |

## Pipeline

| #  | Step                  | Role                                                                              |
| -- | --------------------- | --------------------------------------------------------------------------------- |
| 00 | `step-00-init.md`     | Parses args, requires `/snap:init`, validates the feature state, loads PRD + journey refs. |
| 01 | `step-01-collect.md`  | Fetches the PRD page content, the current journey pages, and the feature's ticket-level git diff. |
| 02 | `step-02-update.md`   | Per impacted journey: AI generates a patch (`mode=diff`) or a full rewrite (`mode=rewrite`). |
| 03 | `step-03-publish.md`  | Pushes the updates via `docs-adapter --action=update-page-content`.               |
| 04 | `step-04-finish.md`   | Telemetry + progress entry. Terminal.                                             |

Steps are **idempotent**: re-running with the same feature + same git state
produces the same diff (modulo AI non-determinism — review before push).

## Outputs

- Updated journey page(s) on AFFiNE / Notion (the PRD page stays intact).
- `progress.json` entry: `doc-update step-04 finish — ok` (or `dry-run` / `skip`).
- `doc-update` telemetry event.

## Next step

Terminal — the feature is shipped and its docs are up to date.
