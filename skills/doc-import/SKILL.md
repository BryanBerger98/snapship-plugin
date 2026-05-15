---
name: doc-import
description: Bootstrap-import legacy doc pages (AFFiNE/Notion) into the snap v1.0 hierarchy (functional_root → domain → user journey). One-shot per project; produces _taxonomy.json. Three strategies: synthesize (default), copy, move.
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, AskUserQuestion
---

# /snap:doc-import — bootstrap legacy docs into snap structure

Run this skill **once per project** when onboarding a codebase that already has
free-form doc pages on AFFiNE / Notion. Produces a populated `Product Docs/`
hierarchy + `.snap/manifests/_taxonomy.json` so subsequent `/snap:define` runs
can lookup-or-create journey pages by slug.

## Prerequisite

- `/snap:init` already run (`snapship.config.json` + `.snap/` exist)
- `documentation.platform` ∈ {affine, notion} (skip if `none`)
- MCP server for that platform reachable in current session
- `.snap/manifests/_taxonomy.json` empty (no `domains[]`) OR `--force` set
  (refuse to clobber existing import)

## When to use

- Existing project with scattered legacy doc pages — too much to manually
  re-organize before first `/snap:define`.
- One-shot bootstrap. Re-runs require `--force` (typically only after a
  failed dry-run or to re-do the analysis with adjusted source root).

## Pipeline

| # | Step | Purpose |
|---|------|---------|
| 00 | `step-00-init.md` | Parse args, require `/snap:init`, validate platform + MCP, guard `_taxonomy.json` non-empty |
| 01 | `step-01-crawl.md` | List source pages (`--source-page` subtree or workspace root), build page index |
| 02 | `step-02-analyze.md` | AI proposes domains + journeys + page→target mapping; emits `proposed_structure` JSON |
| 03 | `step-03-confirm.md` | AskUserQuestion review; allow JSON edit before commit |
| 04 | `step-04-restructure.md` | Execute strategy (synthesize / copy / move); write pages via docs-adapter |
| 05 | `step-05-finish.md` | Persist `_taxonomy.json`, telemetry, progress entry |

## Args

```
/snap:doc-import
  --source-page=<page-id-or-url>     # AFFiNE root to scan (omit = workspace root)
  --strategy=synthesize|copy|move    # default: synthesize
  [--dry-run]                        # preview mapping; no AFFiNE writes
  [--backup]                         # export source pages to .snap/.backup/
  [-a|--auto]                        # autonomous (skip confirms; uses AI proposal as-is)
  [--force]                          # bypass non-empty _taxonomy.json guard
```

## Strategies

| Strategy | Mechanic | Use when |
|----------|----------|----------|
| **synthesize** (default) | AI consolidates N source pages → 1 journey doc. Source pages tagged `[snap-imported]`. | Doc legacy is messy/scattered. |
| **copy** | Duplicate source content to new pages under snap path. Originals moved to `Archive/imported-{date}/`. | Preserve content verbatim. |
| **move** | Rename + reparent source pages to snap path. Preserves AFFiNE history. | Doc already well-structured, just wrong path. |

## Outputs

- `Product Docs/{domain}/{journey}` pages populated on AFFiNE/Notion
- `.snap/manifests/_taxonomy.json` filled (domain + journey page IDs cached)
- `.snap/.backup/` archive (if `--backup`)
- `progress.json` entry + telemetry event `doc-import`
- **Not produced**: `Change Requests/*` (PRDs come via future `/snap:define`),
  feature manifests (no `feature_id` exists yet)

## How to run a step

Read the active step file (start with `step-00-init.md`), follow its instructions
exactly, then move to the file in its `next_step` frontmatter. Stop at a step with
no `next_step` (terminal).

Steps are **idempotent re-entrant on partial fail**: pages already migrated carry
the tag `[snap-imported]` and are skipped on re-run.
