# `/snap:doc-update` — refresh living functional docs

Updates the journey pages impacted by a feature after it ships. Reads the
PRD + current journey content + the feature's git diff, then patches or
rewrites the journey pages via AI. **v1.2** adds an Epic-ship mode that
emits a high-level product section when every child of an Epic is
`done` on the tracker.

## What it does

Keep the functional docs **alive** and up to date after shipping.

- The **PRD** page (`Change Requests/{YYYY}/{MM-YYYY}/`) is **never
  modified** — immutable archive of intent.
- The **journey** pages (`Product Docs/{domain}/{journey}/`) are the
  living spec — this skill keeps them current.
- The **Epic ship section** (v1.2, `--epic=<platform_id>` mode) is a
  high-level product write-up emitted on the doc platform when every
  child User Story / Task / Bug of the Epic is `done`. Idempotent;
  re-running on the same Epic with the same content is a no-op.

`/snap:doc-update` **never closes tracker tickets** — Epic auto-close is
`/snap:develop`'s `step-99-post-merge`. This skill only touches the doc
platform.

## When to use it

| Source                  | Condition                                                                                       |
| ----------------------- | ----------------------------------------------------------------------------------------------- |
| Auto post-`/snap:qa`    | `documentation.auto_update_on_qa_success: true` AND the feature reaches `qa-validated`.        |
| Manual (feature mode)   | `/snap:doc-update --feature=NN-slug` — refresh impacted journey pages for one feature.          |
| Manual (Epic-ship mode) | `/snap:doc-update --epic=<platform_id>` — emit the product ship section when every child is `done` on the tracker. |

## Prerequisites

- `/snap:init` ran (`snap.config.json` exists).
- `documentation.platform ∈ {affine, notion}` (skipped if `none`).
- MCP for that platform reachable.
- **Feature mode**: the feature has a `manifest.json` with `state ==
  "qa-validated"` and `refs.prd.page_id` set. Every
  `impacted_journeys[]` entry has a matching entry in
  `_taxonomy.json`.
- **Epic mode**: the Epic exists on the tracker; its children are
  fetched live to check the all-done condition.

## Syntax

```
/snap:doc-update --feature=NN-slug    [--mode=diff|rewrite] [--dry-run] [-a]
/snap:doc-update --epic=<platform_id> [--dry-run] [-a]
```

`--feature` and `--epic` are mutually exclusive — one or the other.

## Flags

| Flag                              | Effect                                                                                          |
| --------------------------------- | ----------------------------------------------------------------------------------------------- |
| `--feature=NN-slug`               | Feature mode: partial-match on `story_id` (e.g. `01` → `01-auth`). Refreshes impacted journey pages. |
| `--epic=<platform_id>`            | Epic-ship mode: fetches the Epic + its children live; emits a product section only when **every** child is `done`. |
| `--mode=diff\|rewrite`            | Feature mode only — override `documentation.auto_update_mode`. `diff` = AI patch, `rewrite` = full rewrite. |
| `--dry-run`                       | Render the proposed updates locally, do not push to AFFiNE / Notion.                            |
| `-a` / `--auto`                   | Skip confirmation prompts (used by the post-QA hook).                                           |

## Pipeline

| #   | Step                          | Role                                                                                  |
| --- | ----------------------------- | ------------------------------------------------------------------------------------- |
| 00  | `step-00-init.md`             | Parse args, require `/snap:init`, route between feature and Epic modes.               |
| 01  | `step-01-collect.md`          | Feature mode — fetch PRD page content, current journey pages, ticket-level git diff.  |
| 01b | `step-01b-epic-ship.md`       | Epic mode — fetch Epic + children live, check all-done, generate the product ship section. **Terminal**. |
| 02  | `step-02-update.md`           | Feature mode — per impacted journey, AI generates a patch (`diff`) or full rewrite (`rewrite`). |
| 03  | `step-03-publish.md`          | Feature mode — push updates via `docs-adapter --action=update-page-content`.          |
| 04  | `step-04-finish.md`           | Telemetry + progress entry. Terminal for feature mode.                                |

Steps are **idempotent** — re-running with the same feature + git state
(or same Epic + tracker state) produces the same diff (modulo AI
non-determinism — review before push).

## Epic-ship behaviour (`--epic=<platform_id>`)

1. Fetch the Epic live via `tickets-adapter.sh`.
2. List its children via `tracker_list_children` (User Stories, Tasks,
   Bugs).
3. **All-done gate** — every child must be `done` / `closed` on the
   tracker.
   - When the gate passes: emit a top-level product section on the doc
     platform with:
     - Epic description (from the tracker ticket).
     - `business_goal` and `success_metrics` when present.
     - A summary list of shipped User Stories (title + tracker link +
       1-line summary).
   - When the gate fails: skip with a clear message
     (`Epic X: Y/N children done — waiting`). No write to the doc
     platform.
4. **Idempotence** — the section content is hashed and stored either
   on the doc page or in the Epic ticket body; a re-run on unchanged
   state is a no-op.
5. **No tracker write** — `/snap:doc-update` never closes the Epic or
   touches its status. Tracker auto-close is `/snap:develop --post-merge`.

## Outputs

- Feature mode — updated journey page(s) on AFFiNE / Notion (PRD page
  untouched).
- Epic mode — product ship section appended to the platform doc
  (idempotent; content hash stored to skip subsequent re-runs).
- `progress.json` entry: `doc-update step-04 finish — ok` (or
  `dry-run` / `skip`).
- `doc-update` telemetry event.

## Examples

```bash
# Refresh journey pages impacted by feature 01-auth.
/snap:doc-update --feature=01

# Emit the product ship section for an Epic once every child is done.
/snap:doc-update --epic=AUTH-1

# Dry-run an Epic write-up before pushing.
/snap:doc-update --epic=AUTH-1 --dry-run

# Skip confirmation prompts (used by the post-QA auto-trigger).
/snap:doc-update --feature=01 -a
```

## Next step

Terminal — the feature is shipped and its docs are up to date. For
Epic-ship mode, the matching tracker auto-close happens out-of-band via
`/snap:develop --post-merge --ticket=<epic-child-id>` once the
underlying PR merges.
