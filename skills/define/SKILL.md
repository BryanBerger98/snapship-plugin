---
name: define
description: Build per-feature PRDs (change-request format) for a product from vision, personas, and features. Drives a guided AskUserQuestion flow and pushes the result to AFFiNE/Notion via docs-adapter. Materializes .snap/manifests/{slug}.manifest.json per feature.
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, AskUserQuestion
---

# /snap:define — product definition skill

Run this skill to **bootstrap or extend a product's PRDs** before any ticket
exists.

## Prerequisite

Run `/snap:init` once per project first. This skill exits early if
`snap.config.json` is missing.

## When to use

- Greenfield project after init: no manifests yet → full PRD walkthrough.
- Existing project: extend with new feature(s) — keeps prior manifests intact.
- Resume: `--resume` (`-r`) restarts from the last in-flight step recorded in
  `.snap/progress.json`.

## Pipeline

The skill runs 6 ordered steps. Each step is an isolated markdown file with
frontmatter `next_step` pointing to its successor. The orchestrator (this file)
reads steps in order; the model reads only the active step's body.

| # | Step | Purpose |
|---|------|---------|
| 00 | `step-00-init.md`     | Parse args, require `snap.config.json`, detect codebase, branch greenfield vs extension |
| 01 | `step-01-vision.md`   | Ask vision + north star metric |
| 02 | `step-02-personas.md` | Ask 1-N personas |
| 03 | `step-03-features.md` | Ask features list with priorities, domains, impacted journeys |
| 04 | `step-04-render.md`   | Render `.snap/PRDs/{slug}.md` + materialize `manifests/{slug}.manifest.json` |
| 05 | `step-05-publish.md`  | Push PRD page, ensure domain + journey pages exist, ack refs into manifest (trash staging) |

## Args

```
/snap:define [--resume|-r] [--lang=fr|en] [--feature=NN-slug]
```

- `--resume` / `-r` : resume from last in-flight step in `.snap/progress.json`.
  Partial-match the story_id (e.g. `01` matches `01-auth`). If no in-flight
  run, falls through to step-00.
- `--lang` : force PRD language (default: detect from existing or ask).
- `--feature` : skip greenfield path, jump to per-feature PRD for an existing
  `story_id`.

## Outputs

Local (staging — trashed after successful push to remote in step-05) :

- `.snap/PRDs/{story_id}.md` — PRD markdown source.

Local (persistent — references to remote) :

- `.snap/manifests/{story_id}.manifest.json` — schema_version, story_id,
  story_name, state, priority, domains[], impacted_journeys[], refs.{prd,
  …} after publish.
- `.snap/manifests/_taxonomy.json` — domain + journey page IDs cached
  (idempotent across re-runs and across features).

Local (runtime — gitignored) :

- `.snap/progress.json` — in-flight skill state, purged on terminal-step ok.
- `.snap/telemetry.ndjson` — append-only event log.

Remote (single source of truth — per `/snap:init` `documentation.platform`) :

- PRD page at `{prd_root}/{YYYY}/{MM-YYYY}/{NN-feature}` (immutable archive,
  tagged with impacted domains).
- Domain + journey pages under `{functional_root}/{domain}/{journey}` (living
  spec, body populated later by `/snap:doc-update`).

v0.1's `prd-global.md` and v0.2's `meta.json` are dropped — see
`docs/contributing/decisions.md` "PRD archive vs doc fonctionnelle vivante" + "Manifest unifié
v1.0".

## How to run a step

Read the active step file (start with `step-00-init.md` unless `--resume` says
otherwise), follow its instructions exactly, then move to the file referenced in
its `next_step` frontmatter. Stop when a step has no `next_step` (terminal) or
when the user aborts.

Steps are **idempotent** — re-running step-NN with the same inputs produces the
same output. Re-runs are safe (step-05 in particular skips already-synced
features).
