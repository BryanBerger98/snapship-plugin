---
name: define
description: Multimode router skill — `vision` (workspace narrative + principles + north star), `journey` (user journeys + steps + outcomes), or `story` (per-feature PRDs in change-request format). Auto-detects mode from prompt or `--mode=` flag, runs LLM concertation, then branches to the correct sub-flow. Story mode pushes PRDs to AFFiNE/Notion via docs-adapter and materializes `.snap/manifests/{slug}.manifest.json` per feature.
when_to_use: Start or extend product knowledge before any ticket — vision (workspace narrative), journey (user flows), or story (per-feature PRDs). Idempotent across re-runs.
argument-hint: "[--mode=vision|journey|story] [--resume|-r] [--lang=fr|en] [--story=NN-slug] [--epic=PARENT_EPIC_ID]"
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, AskUserQuestion
---

# /snap:define — product definition skill (multimode)

Router skill bootstraps or extends product knowledge in one of three modes.
`step-00-detect-mode` resolves the mode (prompt heuristic + LLM concertation,
or explicit `--mode=`) then branches.

## Prerequisite

Run `/snap:init` once per project. Skill aborts if `snap.config.json` missing.

## Modes

| Mode      | Outcome                                                      | Terminal step             |
|-----------|--------------------------------------------------------------|---------------------------|
| `vision`  | Edits workspace vision/principles/north-star in `_taxonomy.json` | `step-00-vision-edit`  |
| `journey` | Creates / refactors / splits user journeys in `_taxonomy.json`   | `step-00-journey-edit` |
| `story`   | Captures features, renders PRD, pushes one page per feature      | `step-05-publish`      |

## Pipeline

Single entry point — `step-00-detect-mode.md` (router). Branches by mode :

| Mode      | Steps after router                                                                |
|-----------|-----------------------------------------------------------------------------------|
| `vision`  | `step-00-vision-edit` (terminal)                                                  |
| `journey` | `step-00-journey-edit` (terminal)                                                 |
| `story`   | `step-00-story-init` → `01-vision` → `02-personas` → `03-features` → `04-render` → `05-publish` |

All steps idempotent — re-running with same inputs produces same output.
Re-runs safe : `step-05` skips already-synced features, `_taxonomy.json`
mutations merge.

## How to run

1. Read `step-00-detect-mode.md` — always the entry point unless `--resume`
   redirects to the in-flight step.
2. Follow the resolved `next_step` chain. Stop when a step has no `next_step`
   (terminal) or user aborts.
3. State lives in `.snap/.define-state.json` (mode cache) and
   `.snap/progress.json` (in-flight tracking). Both purged on terminal-step OK.

## User-facing reference

Full flag reference, examples, output layout, and per-mode details live in
`docs/usage/skills/define.md`. Lexicon used by the router lives in
`skills/define/_keywords.json` (loaded by `step-00-detect-mode`, not here).
