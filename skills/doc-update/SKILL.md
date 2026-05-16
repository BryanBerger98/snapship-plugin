---
name: doc-update
description: Refresh living functional doc (journey pages) post-ship. Reads PRD + current journey content + git diff for the feature, AI-patches or rewrites impacted journey pages. v1.2 — supports --epic=<id> mode to generate a product-level ship section when all child US/Tasks are done on the tracker. Triggered automatically post-/snap:qa or manually via --feature / --epic flag.
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
---

# /snap:doc-update — refresh living functional doc (v1.2)

Run this skill **after a feature ships** to update the journey pages it impacts.

The PRD page (under `Change Requests/{YYYY}/{MM-YYYY}/`) is **never modified** —
it's an immutable archive of intent. The journey pages (under `Product Docs/{domain}/{journey}/`)
are the living spec; this skill keeps them current.

**v1.2 — Epic ship section** : with `--epic=<id>`, when every child ticket
(US/Task/Bug) of the Epic is `done` on the tracker, the skill generates a
top-level product section (description + business goal + success metrics +
shipped US list) on the documentation platform. Idempotent — content hashed
and skipped if already present. Does **not** auto-close the Epic ticket — that
is `/develop` step-99's job.

## Prerequisite

- `/snap:init` already run (`snap.config.json` exists)
- `documentation.platform` ∈ {affine, notion} (skip if `none`)
- MCP for that platform reachable
- Feature manifest (`.snap/manifests/${story_id}.manifest.json`) has `state == "qa-validated"` and `refs.prd.page_id` populated
- Each `impacted_journeys[]` entry has a corresponding cache entry in `_taxonomy.json`

## Trigger

| Source | Condition |
|--------|-----------|
| Auto post-`/snap:qa` | `documentation.auto_update_on_qa_success: true` AND feature state transitions to `qa-validated` |
| Manual feature mode | `/snap:doc-update --feature=NN-slug` |
| Manual Epic-ship | `/snap:doc-update --epic=<platform_id>` (v1.2) |

## Pipeline

| # | Step | Purpose |
|---|------|---------|
| 00 | `step-00-init.md` | Parse args, require `/snap:init`, route between feature and Epic modes |
| 01 | `step-01-collect.md` | (feature mode) Fetch PRD page content, current journey pages, ticket-level git diff |
| 01b | `step-01b-epic-ship.md` | (Epic mode) Fetch Epic + children live, check all-done, generate product ship section. **Terminal**. |
| 02 | `step-02-update.md` | (feature mode) Per impacted journey: AI generates patch (`diff`) or full rewrite (`rewrite`) |
| 03 | `step-03-publish.md` | (feature mode) Push updates via `docs-adapter --action=update-page-content` |
| 04 | `step-04-finish.md` | Telemetry + progress entry. Terminal for feature mode. |

## Args

```
/snap:doc-update --feature=NN-slug [--mode=diff|rewrite] [--dry-run] [-a]
/snap:doc-update --epic=<platform_id>  [--dry-run] [-a]   # v1.2 Epic ship mode
```

- `--feature` (mutually exclusive with `--epic`): partial-match on `story_id`
  (e.g. `01` → `01-auth`). Updates impacted journey pages.
- `--epic=<platform_id>`: Epic ship mode — fetches the Epic live, lists its
  children, and only generates the product ship section when *every* child is
  `done` on the tracker. Otherwise skips with `Epic X: Y/N done — waiting`.
- `--mode`: override `documentation.auto_update_mode` (feature mode only).
- `--dry-run`: render proposed updates locally, do not push to AFFiNE/Notion.
- `-a` / `--auto`: skip confirmation prompts (used by post-QA hook).

## Outputs

- Journey page(s) on AFFiNE/Notion updated (PRD page untouched).
- Epic mode : product ship section appended to the platform doc (idempotent —
  content hash stored on the page or in the Epic ticket body; skipped on re-run).
- `progress.json` entry: `doc-update step-04 finish — ok` (or `dry-run` / `skip`).
- Telemetry event `doc-update`.

## How to run a step

Read the active step file (start with `step-00-init.md`), follow it exactly,
then move to the `next_step` frontmatter target. Stop at a step with no `next_step`.

Steps are **idempotent**: re-running with the same feature + git state produces
the same diff (modulo AI nondeterminism — review before push).
