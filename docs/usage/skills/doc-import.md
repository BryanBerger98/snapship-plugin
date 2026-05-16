# `/snap:doc-import` — import existing docs into the SnapShip structure

Imports free-form doc pages (AFFiNE / Notion) into the SnapShip
hierarchy (`functional_root` → domain → user journey). One-shot per project;
produces `_taxonomy.json`.

## What it does

Onboard a codebase that already has scattered doc pages. Produces a
populated `Product Docs/` hierarchy + `_taxonomy.json`, so that subsequent
`/snap:define` runs can find-or-create journey pages by slug.

## When to use it

- Existing project with scattered doc pages, too many to
  reorganize by hand before the first `/snap:define`.
- **One-shot** bootstrap. Re-runs require `--force` (typically after a
  failed dry-run or to redo the analysis with a different source root).

## Prerequisites

- `/snap:init` run (`snap.config.json` + `.snap/` exist).
- `documentation.platform ∈ {affine, notion}` (skipped if `none`).
- MCP server for that platform reachable in the current session.
- `_taxonomy.json` empty **or** `--force` (refuses to overwrite an existing import).

## Syntax

```
/snap:doc-import
  --source-page=<page-id-or-url>     # AFFiNE root to scan (omit = workspace root)
  --strategy=synthesize|copy|move    # default: synthesize
  [--dry-run]                        # previews the mapping; no writes
  [--backup]                         # exports source pages to .snap/.backup/
  [-a|--auto]                        # autonomous (skips confirmations; uses AI proposal as-is)
  [--force]                          # bypasses the non-empty _taxonomy.json guard
```

## Flags

| Flag                     | Effect                                                                         |
| ------------------------ | ------------------------------------------------------------------------------ |
| `--source-page=<id\|url>`| AFFiNE root to scan. Omit → workspace root.                                    |
| `--strategy=...`         | Import strategy (see below). Default: `synthesize`.                            |
| `--dry-run`              | Previews the page → target mapping, no AFFiNE writes.                          |
| `--backup`               | Exports source pages to `.snap/.backup/`.                                      |
| `-a` / `--auto`          | Autonomous: skips confirmations, uses the AI proposal as-is.                   |
| `--force`                | Bypasses the "non-empty `_taxonomy.json`" guard.                               |

## Strategies

| Strategy                 | Mechanics                                                                                       | Use when                                  |
| ------------------------ | ----------------------------------------------------------------------------------------------- | ----------------------------------------- |
| **synthesize** (default) | AI consolidates N source pages → 1 journey doc. Source pages tagged `[snap-imported]`.           | Legacy docs are messy / scattered.        |
| **copy**                 | Duplicates source content into new pages under the SnapShip path. Originals go to `Archive/imported-{date}/`. | Preserve content verbatim.                |
| **move**                 | Renames + reparents source pages into the SnapShip path. Preserves AFFiNE history.              | Docs are already well-structured, just at the wrong path. |

## Pipeline

| #  | Step                     | Role                                                                          |
| -- | ------------------------ | ----------------------------------------------------------------------------- |
| 00 | `step-00-init.md`        | Parses args, requires `/snap:init`, validates platform + MCP, enforces non-empty `_taxonomy.json` guard. |
| 01 | `step-01-crawl.md`       | Lists source pages (`--source-page` subtree or workspace root), builds the index. |
| 02 | `step-02-analyze.md`     | AI proposes domains + journeys + page → target mapping; emits `proposed_structure` JSON. |
| 03 | `step-03-confirm.md`     | Review via `AskUserQuestion`; JSON edits possible before commit.               |
| 04 | `step-04-restructure.md` | Executes the strategy (synthesize / copy / move); writes pages via docs-adapter. |
| 05 | `step-05-finish.md`      | Persists `_taxonomy.json`, telemetry, progress entry.                          |

Steps are **idempotent and re-entrant on partial failure**: already-migrated
pages carry the `[snap-imported]` tag and are skipped on re-run.

## Outputs

- `Product Docs/{domain}/{journey}` pages populated on AFFiNE / Notion.
- `.snap/manifests/_taxonomy.json` filled (domain + journey page IDs).
- `.snap/.backup/` (if `--backup`).
- `progress.json` entry + `doc-import` telemetry event.
- **Not produced**: `Change Requests/*` (PRDs come from `/snap:define`),
  feature `manifest.json` (no `story_id` exists yet).

## Next step

`/snap:define` to scope the first feature in the imported structure.
