# `/snap:define` — product definition (multimode)

Router skill with three modes — `vision`, `journey`, `story`. Auto-detects
the mode from your prompt (heuristic + LLM concertation) or accepts an
opt-in `--mode=` flag. `vision` and `journey` edit the workspace
taxonomy locally; `story` runs the full PRD flow and pushes one page per
feature to AFFiNE / Notion.

## What it does

Establish or extend product knowledge **before any ticket**:

- **`vision`** — capture the product vision, principles, and north-star
  metric in `_taxonomy.json`. Local-only artefact, no doc-platform push.
- **`journey`** — create / refactor / split user journeys (steps +
  outcomes) in `_taxonomy.json`. Local-only artefact; the remote page
  is created later by `/snap:doc-update`.
- **`story`** — full PRD flow. Greenfield (vision → personas → features)
  or extension (add one or more features). Pushes one PRD page per
  feature to AFFiNE / Notion as the deliverable.

## When to use it

- Right after `/snap:init` on a new project — start in `vision`, then
  `journey`, then `story` (or rely on auto-detection from your prompt).
- On an existing project — extend any of the three artefacts. Every mode
  is idempotent.
- To resume after an interruption — `--resume` reads the in-flight step
  from `.snap/progress.json` regardless of mode.

## Prerequisites

`/snap:init` ran once per project. The skill exits early if
`snap.config.json` is missing.

## Modes

| Mode      | Trigger                                                  | Deliverable                                 |
| --------- | -------------------------------------------------------- | ------------------------------------------- |
| `vision`  | keywords: vision, mission, principles, north star, …      | `_taxonomy.json.workspace.*` (local-only)   |
| `journey` | keywords: parcours, flow, user steps, scenario, …         | `_taxonomy.json.journeys[]` (local-only)    |
| `story`   | keywords: feature, PRD, story, … (also the default)       | PRD page per feature on AFFiNE / Notion + manifests |

### Auto-detection

`step-00-detect-mode` runs a hybrid heuristic + LLM concertation on the
raw input:

- FR / EN keyword scan first (cheap signal).
- LLM concertation for ambiguous prompts.
- User confirms the proposed mode via `AskUserQuestion` before the
  branch is taken.
- The chosen mode is persisted in `.snap/.define-state.json` so resume
  knows where it landed.

### Opt-in via `--mode=`

Pass `--mode=vision|journey|story` to skip the detection prompt
entirely.

### What gets pushed where

| Mode      | Local mutation                                  | Remote push                                 |
| --------- | ----------------------------------------------- | ------------------------------------------- |
| `vision`  | `_taxonomy.json.workspace.{vision,principles,north_star}` | none                            |
| `journey` | `_taxonomy.json.journeys[]`                     | none (page created by `/snap:doc-update`)   |
| `story`   | `manifests/{slug}.manifest.json` + `PRDs/{slug}.md` staging | PRD page + domain / journey scaffolds |

## Syntax

```
/snap:define [--mode=vision|journey|story] [--resume|-r] [--lang=fr|en]
             [--feature=NN-slug] [--epic=PARENT_EPIC_ID]
```

## Flags

| Flag                              | Effect                                                                                          |
| --------------------------------- | ----------------------------------------------------------------------------------------------- |
| `--mode=vision\|journey\|story`   | Force the mode and skip auto-detection.                                                         |
| `--resume` / `-r`                 | Resume the last in-flight step from `progress.json` (partial-match on `story_id`).              |
| `--lang=fr\|en`                   | Force the PRD language (default: detect from an existing PRD, otherwise prompt).                |
| `--feature=NN-slug`               | `story` mode only — skip greenfield and jump to the PRD of an existing `story_id`.              |
| `--epic=PARENT_EPIC_ID`           | `story` mode only — apply this parent Epic ID to every feature captured in the run.             |

## Pipeline

All modes share a single entry point: `step-00-detect-mode`.

### Mode `vision` (terminal at step-00)

| # | Step                          | Role                                                                                |
|---|-------------------------------|-------------------------------------------------------------------------------------|
| 00 | `step-00-detect-mode.md`     | Router — detects the mode and branches.                                             |
| 00 | `step-00-vision-edit.md`     | Edits `workspace.vision`, `workspace.principles[]`, `workspace.north_star` in `_taxonomy.json`. Terminal. |

### Mode `journey` (terminal at step-00)

| # | Step                          | Role                                                                                |
|---|-------------------------------|-------------------------------------------------------------------------------------|
| 00 | `step-00-detect-mode.md`     | Router.                                                                             |
| 00 | `step-00-journey-edit.md`    | Creates / refactors / splits journeys (steps + outcomes) in `_taxonomy.json`. Terminal. |

### Mode `story` (5 steps after the router)

| # | Step                          | Role                                                                                |
|---|-------------------------------|-------------------------------------------------------------------------------------|
| 00 | `step-00-detect-mode.md`     | Router.                                                                             |
| 00 | `step-00-story-init.md`      | Parse args, require config, detect codebase, branch greenfield vs extension.        |
| 01 | `step-01-vision.md`          | Capture vision + north-star metric (cache state).                                   |
| 02 | `step-02-personas.md`        | Ask 1 to N personas.                                                                |
| 03 | `step-03-features.md`        | Ask the feature list (priorities, parent Epic, domains, impacted journeys).         |
| 04 | `step-04-render.md`          | Render `.snap/PRDs/{slug}.md` + materialize `manifests/{slug}.manifest.json`.       |
| 05 | `step-05-publish.md`         | Push the PRD page, ensure domain + journey pages exist, ack refs (trash staging).   |

Steps are **idempotent** — re-running a step with the same inputs produces
the same output. Re-runs are safe (`step-05` skips already-synced features
and `_taxonomy.json` mutations are merging).

## Outputs

### Mode `vision`

Persistent (local-only):

- `.snap/manifests/_taxonomy.json.workspace.{vision,principles,north_star}`.

### Mode `journey`

Persistent (local-only):

- `.snap/manifests/_taxonomy.json.journeys[]` — each entry has
  `state` (`draft` | `synced`), `steps[]`, `outcomes[]`.

`state=draft` (no `page_id`) means the journey is local-only. The remote
page is created by `/snap:doc-update` post-validation.

### Mode `story`

Local (staging — trashed after step-05 push success):

- `.snap/PRDs/{story_id}.md` — PRD markdown source.

Local (persistent — pointers to remote):

- `.snap/manifests/{story_id}.manifest.json` — `schema_version`,
  `story_id`, `story_name`, `state`, `priority`,
  `parent_epic_id` (or `parent_epic_title` + `pending`),
  `domains[]`, `impacted_journeys[]`, `refs.{prd, …}` after publish.
- `.snap/manifests/_taxonomy.json` — domain + journey page IDs cached
  (idempotent across re-runs and features).

Runtime (all modes — gitignored):

- `.snap/progress.json` — in-flight skill state, purged on terminal-step OK.
- `.snap/telemetry.ndjson` — append-only event log.

Remote (mode `story` only — single source of truth):

- PRD page under `{prd_root}/{YYYY}/{MM-YYYY}/{NN-feature}` (immutable
  archive, tagged with impacted domains).
- Domain + journey pages under `{functional_root}/{domain}/{journey}`
  (living spec; body filled later by `/snap:doc-update`).

## Examples

```bash
# Mode detected automatically from the prompt.
/snap:define "Je veux ajouter un parcours d'onboarding rapide"
# → mode journey proposed, confirmed via AskUserQuestion.

# Forced mode via flag.
/snap:define --mode=vision

# Story mode with an imposed parent Epic.
/snap:define --mode=story --epic=AUTH-1
# → step-03 skips the parent-Epic question, applies AUTH-1 to all features.

# Resume — picks up the in-flight step regardless of mode.
/snap:define -r
```

## Next step

- After `vision` / `journey`: usually `/snap:define --mode=story` to
  capture features, or jump straight to `/snap:ticket --standalone` for
  ad-hoc tickets.
- After `story`: `/snap:ticket --story-id=NN-slug` to decompose the
  feature into tickets.
