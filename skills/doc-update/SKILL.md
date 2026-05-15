---
name: doc-update
description: Refresh living functional doc (journey pages) post-ship. Reads PRD + current journey content + git diff for the feature, AI-patches or rewrites impacted journey pages. Triggered automatically post-/snap:qa or manually via --feature flag.
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
---

# /snap:doc-update — refresh living functional doc

Run this skill **after a feature ships** to update the journey pages it impacts.

The PRD page (under `Change Requests/{YYYY}/{MM-YYYY}/`) is **never modified** —
it's an immutable archive of intent. The journey pages (under `Product Docs/{domain}/{journey}/`)
are the living spec; this skill keeps them current.

## Prerequisite

- `/snap:init` already run (`snapship.config.json` exists)
- `documentation.platform` ∈ {affine, notion} (skip if `none`)
- MCP for that platform reachable
- Feature manifest (`.snap/manifests/${feature_id}.manifest.json`) has `state == "qa-validated"` and `refs.prd.page_id` populated
- Each `impacted_journeys[]` entry has a corresponding cache entry in `_taxonomy.json`

## Trigger

| Source | Condition |
|--------|-----------|
| Auto post-`/snap:qa` | `documentation.auto_update_on_qa_success: true` AND feature state transitions to `qa-validated` |
| Manual | `/snap:doc-update --feature=NN-slug` |

## Pipeline

| # | Step | Purpose |
|---|------|---------|
| 00 | `step-00-init.md` | Parse args, require `/snap:init`, validate feature state, load PRD + journey refs |
| 01 | `step-01-collect.md` | Fetch PRD page content, current journey pages, ticket-level git diff for the feature |
| 02 | `step-02-update.md` | Per impacted journey: AI generates patch (`auto_update_mode=diff`) or full rewrite (`=rewrite`) |
| 03 | `step-03-publish.md` | Push updates via `docs-adapter --action=update-page-content` |
| 04 | `step-04-finish.md` | Telemetry + progress entry. Terminal. |

## Args

```
/snap:doc-update --feature=NN-slug [--mode=diff|rewrite] [--dry-run] [-a]
```

- `--feature` (required): partial-match on `feature_id` (e.g. `01` → `01-auth`).
- `--mode`: override `documentation.auto_update_mode` (default: from config).
- `--dry-run`: render proposed updates locally, do not push to AFFiNE/Notion.
- `-a` / `--auto`: skip confirmation prompts (used by post-QA hook).

## Outputs

- Journey page(s) on AFFiNE/Notion updated (PRD page untouched).
- `progress.json` entry: `doc-update step-04 finish — ok` (or `dry-run` / `skip`).
- Telemetry event `doc-update`.

## How to run a step

Read the active step file (start with `step-00-init.md`), follow it exactly,
then move to the `next_step` frontmatter target. Stop at a step with no `next_step`.

Steps are **idempotent**: re-running with the same feature + git state produces
the same diff (modulo AI nondeterminism — review before push).
