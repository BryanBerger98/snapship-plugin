---
name: doc-import
description: Bootstrap-import legacy doc pages (AFFiNE/Notion) into the snap v0.2 hierarchy (functional_root → domain → user journey). One-shot per project; produces domains.json. Three strategies: synthesize (default), copy, move.
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, AskUserQuestion
---

# /snap:doc-import — bootstrap legacy docs into snap structure

Run this skill **once per project** when onboarding a codebase that already has
free-form doc pages on AFFiNE / Notion. Produces a populated `Product Docs/`
hierarchy + `domains.json` so subsequent `/snap:define` runs can lookup-or-create
journey pages by slug.

Not a migration tool: snap v0.1 → v0.2 has **no migration** (pilot only).

## Prerequisite

- `/snap:init` already run (`snapship.config.json` + `.claude/product/` exist)
- `documentation.platform` ∈ {affine, notion} (skip if `none`)
- MCP server for that platform reachable in current session
- `domains.json` empty OR `--force` set (refuse to clobber existing import)

## When to use

- Existing project with scattered legacy doc pages — too much to manually
  re-organize before first `/snap:define`.
- One-shot bootstrap. Re-runs require `--force` (typically only after a
  failed dry-run or to re-do the analysis with adjusted source root).

## Pipeline

| # | Step | Purpose |
|---|------|---------|
| 00 | `step-00-init.md` | Parse args, require `/snap:init`, validate platform + MCP, guard `domains.json` non-empty |
| 01 | `step-01-crawl.md` | List source pages (`--source-page` subtree or workspace root), build page index |
| 02 | `step-02-analyze.md` | AI proposes domains + journeys + page→target mapping; emits `proposed_structure` JSON |
| 03 | `step-03-confirm.md` | AskUserQuestion review; allow JSON edit before commit |
| 04 | `step-04-restructure.md` | Execute strategy (synthesize / copy / move); write pages via docs-adapter |
| 05 | `step-05-finish.md` | Persist `domains.json`, telemetry, progress entry |

## Args

```
/snap:doc-import
  --source-page=<page-id-or-url>     # AFFiNE root to scan (omit = workspace root)
  --strategy=synthesize|copy|move    # default: synthesize
  [--dry-run]                        # preview mapping; no AFFiNE writes
  [--backup]                         # export source pages to .claude/product/.backup/
  [-a|--auto]                        # autonomous (skip confirms; uses AI proposal as-is)
  [--force]                          # bypass non-empty domains.json guard
```

## Strategies

| Strategy | Mechanic | Use when |
|----------|----------|----------|
| **synthesize** (default) | AI consolidates N source pages → 1 journey doc. Source pages tagged `[snap-imported]`. | Doc legacy is messy/scattered. |
| **copy** | Duplicate source content to new pages under snap path. Originals moved to `Archive/imported-{date}/`. | Preserve content verbatim. |
| **move** | Rename + reparent source pages to snap path. Preserves AFFiNE history. | Doc already well-structured, just wrong path. |

## Outputs

- `Product Docs/{domain}/{journey}` pages populated on AFFiNE/Notion
- `.claude/product/domains.json` filled (domain + journey page IDs cached)
- `.claude/product/.backup/` archive (if `--backup`)
- `progress.md` entry + telemetry event `doc-import`
- **Not produced**: `Change Requests/*` (PRDs come via future `/snap:define`),
  `meta.json` features (no `feature_id` exists yet)

## How to run a step

Read the active step file (start with `step-00-init.md`), follow its instructions
exactly, then move to the file in its `next_step` frontmatter. Stop at a step with
no `next_step` (terminal).

Steps are **idempotent re-entrant on partial fail**: pages already migrated carry
the tag `[snap-imported]` and are skipped on re-run.
