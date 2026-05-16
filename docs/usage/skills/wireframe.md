# `/snap:wireframe` — UI tickets → low-fi wireframes

Generates low-fi wireframes for a feature's UI tickets via the configured
wireframe platform (Frame0, Penpot, or Figma), builds a Gallery page in the
docs, and back-links the wireframe URLs into the tickets.

## What it does

Take a feature to low-fidelity wireframes **before `/snap:develop`**,
when tickets touch the UI.

## When to use it

- A feature has a `tickets.json` with at least one ticket touching UI
  files (keyword + extension heuristic, step-01).
- A wireframe platform is configured:
  `config.wireframes.platform ∈ {frame0, penpot, figma}`.
- `/snap:define` has filled `prd-feature.md` (screen names + known states).

## Supported platforms

| `wireframes.platform` | Helper                            | Surface                                      |
| --------------------- | --------------------------------- | -------------------------------------------- |
| `frame0`              | `_shared/frame0-helper.sh`        | Desktop app + MCP                            |
| `penpot`              | `_shared/penpot-helper.sh`        | Web app + MCP plugin                         |
| `figma`               | `_shared/figma-helper.sh`         | Figma Desktop + `figma-console-mcp` + Bridge plugin |
| `none` (absent)       | —                                 | Skill skipped                                |

The skill is platform-agnostic at the orchestration layer: step-00 resolves
`config.wireframes.platform` → a helper, and each later step calls it via
the `$helper` variable.

> **Figma**: requires Figma Desktop running, the Desktop Bridge plugin active, and
> a token in `.env.snap` (key `FIGMA_ACCESS_TOKEN`, override
> `wireframes.figma.token_env`). step-00 halts if `figma.fileKey` doesn't match
> `wireframes.figma.file_key`.

## Syntax

```
/snap:wireframe [--resume|-r] [--feature=NN-slug] [--dry-run]
```

## Flags

| Flag                | Effect                                                                           |
| ------------------- | -------------------------------------------------------------------------------- |
| `--resume` / `-r`   | Resumes via `progress.sh resume next --skill=wireframe`.                         |
| `--feature=NN-slug` | Targets the `story_id` (required if multiple features; partial-match).         |
| `--dry-run`         | Helpers return mock descriptors: no MCP calls, no PNG, no doc writes.            |

## Pipeline

| #  | Step                 | Role                                                                       |
| -- | -------------------- | -------------------------------------------------------------------------- |
| 00 | `step-00-init.md`    | Parses args, resolves feature + platform + helper, platform preflight.     |
| 01 | `step-01-filter.md`  | Identifies UI tickets via keyword + extension heuristic.                   |
| 02 | `step-02-design.md`  | Per screen: creates the page, adds shapes, exports the PNG via the helper. |
| 03 | `step-03-gallery.md` | Gallery page in the docs: uploads PNGs, embeds per screen + state.         |
| 04 | `step-04-link.md`    | Updates each UI ticket with `wireframe_url` + `wireframe_screen`.          |

## Outputs

- `.snap/wireframes/{story_id}/{screen-id}-{state}.png` (local cache
  pre-push).
- Gallery page in the docs — ref persisted in
  `manifests/{story_id}.manifest.json` → `refs.wireframes_gallery.{page_id,url,synced_at,sync_status}`.
- `.snap/wireframes/{story_id}/gallery.md` — one section per screen
  (source rendered before doc push).
- Each UI ticket in `.snap/tickets/{story_id}.json` gains
  `wireframe_screen` + `wireframe_url`.

## Next step

`/snap:design` for hi-fi mockups, or `/snap:develop`.
