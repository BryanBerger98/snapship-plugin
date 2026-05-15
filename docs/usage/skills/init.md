# `/snap:init` — workspace bootstrap

Initializes SnapShip in the current project: detects platforms, asks for
confirmation, writes `snapship.config.json`, and creates the `.snap/`
tree.

## What it does

`/snap:init` is the **mandatory entry point**. Every other skill
(`/snap:define`, `/snap:ticket`, `/snap:wireframe`, `/snap:design`,
`/snap:develop`, `/snap:qa`, …) refuses to run if
`snapship.config.json` is missing and points back here.

## When to use it

- **New project**: nothing SnapShip-related exists yet.
- **Adoption on an existing project**: detects `.git/config`, the active
  MCP servers, and the project structure to pre-fill default values.
- **Re-init**: `--force` rewrites an existing `snapship.config.json`
  without touching the contents of `.snap/`.

Run it **once per project**.

## Syntax

```
/snap:init [--auto|-a] [--lang=fr|en] [--force]
```

## Flags

| Flag             | Effect                                                                                                  |
| ---------------- | ------------------------------------------------------------------------------------------------------- |
| `--auto` / `-a`  | Autonomous mode: skips questions and uses each detected value. Fails if a required field stays unresolved (e.g. no docs MCP detected). |
| `--lang=fr\|en`  | Forces `defaults.lang` in the config (default: `fr`).                                                   |
| `--force`        | Rewrites an existing `snapship.config.json`. Safe: does not touch `.snap/`.                             |

## Pipeline

| #  | Step                | Role                                                                          |
| -- | ------------------- | ----------------------------------------------------------------------------- |
| 00 | `step-00-detect.md` | Probes the environment, proposes answers via `AskUserQuestion` (or auto).     |
| 01 | `step-01-write.md`  | Writes `snapship.config.json`, creates `.snap/`, validates against the schema. |

Steps are **idempotent**: re-running `step-01-write` with `--force` on
identical inputs produces an identical config.

## Outputs

- `<project>/snapship.config.json` — validated against `config.schema.json`.
- `<project>/.snap/`:
  ```
  .snap/
    features/
    progress.json            # run journal (header only at init)
    telemetry.ndjson       # ready for append via skills/_shared/telemetry.sh
    .config-resolved.json  # produced by load-config.sh
  ```
- Telemetry entry `init step-01 write — ok`.

## Next step

`/snap:define` to draft the PRD of the first feature.
