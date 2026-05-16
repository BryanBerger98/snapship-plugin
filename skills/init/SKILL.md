---
name: init
description: Bootstrap an snap workspace in the current project — detect platforms, ask the user to confirm, write `snap.config.json`, scaffold `.snap/`. Run once before `/snap:define`.
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, AskUserQuestion
---

# /snap:init — workspace bootstrap

Run this skill **once per project** before any other snap skill. It writes the
project-level config (`snap.config.json`) and scaffolds the local workspace
(`.snap/`). All other skills (`/snap:define`, `/snap:ticket`, `/snap:wireframe`,
`/snap:design`, `/snap:develop`, `/snap:qa`) require this config to exist and
exit early with a pointer back here when it does not.

## When to use

- Greenfield project: nothing snap-related exists yet.
- Re-init: `--force` overwrites an existing `snap.config.json` (preserves
  `.snap/` content).
- Adopting snap in an existing repo: detects `.git/config`, available MCPs,
  and project structure to pre-fill defaults.

## Pipeline

| # | Step | Purpose |
|---|------|---------|
| 00 | `step-00-detect.md` | Probe environment, render answers via `AskUserQuestion` (or auto) |
| 01 | `step-01-write.md`  | Write `snap.config.json`, scaffold `.snap/`, validate |

## Args

```
/snap:init [--auto|-a] [--lang=fr|en] [--force]
```

- `--auto` / `-a` : autonomous mode — skip prompts, use every detected default.
  Fails if any required field is unresolved (e.g. no MCP detected for docs).
- `--lang` : force config `defaults.lang` (default: `fr`).
- `--force` : overwrite an existing `snap.config.json`. Safe — does not touch
  `.snap/`.

## Outputs

- `<project>/snap.config.json` (validated against `config.schema.json`)
- `<project>/.snap/` workspace tree :
  ```
  .snap/
    manifests/
      _taxonomy.json       # domains + journeys + workspace remote root
    PRDs/                  # per-feature PRD source (staging before push)
    designs/               # per-feature design assets (staging)
    wireframes/            # per-feature wireframes (staging)
    tickets/               # per-feature ticket bundles (staging)
    queues/                # per-feature dev queues (runtime, gitignored)
    progress.json          # runtime skill state (gitignored)
    telemetry.ndjson       # event log (gitignored)
    .doc-import/cache/     # ephemeral doc-import cache (gitignored)
  ```
- Telemetry entry `init step-01-write — ok`.

## How to run a step

Read the active step file (`step-00-detect.md` first), follow it exactly, then
move to the file referenced in its `next_step` frontmatter. Stop at a terminal
step or on user abort.

Steps are **idempotent** — re-running `step-01-write` with `--force` against
identical inputs produces an identical config.

## Suggest next

After completion, suggest `/snap:define` to start the first feature PRD.
