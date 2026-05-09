---
name: define
description: Build PRDs (global + per-feature) for a product from vision, personas, and features. Drives a guided AskUserQuestion flow and pushes the result to AFFiNE/Notion via docs-adapter.
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, AskUserQuestion
---

# /define — product definition skill

Run this skill to **bootstrap or extend a product's PRD** before any ticket exists.

## Prerequisite

Run `/artysan:init` once per project first. This skill exits early if
`artysan.config.json` is missing.

## When to use

- Greenfield project after init: no `prd-global.md` yet → full PRD walkthrough.
- Existing project: `.claude/product/prd-global.md` exists → extend with new feature(s).
- Resume: `--resume` (`-r`) restarts from the last successful step recorded in `progress.md`.

## Pipeline

The skill runs 6 ordered steps. Each step is an isolated markdown file with frontmatter
`next_step` pointing to its successor. The orchestrator (this file) reads the steps in
order; when blocked the model reads only the active step's body.

| # | Step | Purpose |
|---|------|---------|
| 00 | `step-00-init.md` | Parse args, require `artysan.config.json`, detect codebase, branch greenfield vs extension |
| 01 | `step-01-vision.md` | Ask vision + north star metric |
| 02 | `step-02-personas.md` | Ask 1-N personas |
| 03 | `step-03-features.md` | Ask features list with priorities |
| 04 | `step-04-render.md` | Render `prd-global.md` + per-feature PRDs from templates |
| 05 | `step-05-publish.md` | Push to AFFiNE/Notion via docs-adapter, update progress |

## Args

```
/define [--resume|-r] [--lang=fr|en] [--feature=NN-slug]
```

- `--resume` / `-r`: resume from last successful step in `progress.md`. Partial-match the
  feature_id (e.g. `01` matches `01-auth`). If no in-flight run, falls through to step-00.
- `--lang`: force PRD language (default: detect from existing PRD or ask).
- `--feature`: skip greenfield path, jump to per-feature PRD for an existing `feature_id`.

## Outputs

- `.claude/product/prd-global.md`
- `.claude/product/features/{feature_id}/prd-feature.md` (one per feature)
- `.claude/product/features/{feature_id}/meta.json` (state=`defined`)
- `.claude/product/progress.md` (append-only run log)
- AFFiNE / Notion pages (URLs cached in meta.json)

## How to run a step

Read the active step file (start with `step-00-init.md` unless `--resume` says otherwise),
follow its instructions exactly, then move to the file referenced in its `next_step`
frontmatter field. Stop when a step has no `next_step` (terminal) or when the user aborts.

Steps are **idempotent** — re-running step-NN with the same inputs produces the same
output. Re-runs are safe.
