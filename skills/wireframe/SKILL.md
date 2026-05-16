---
name: wireframe
description: Generate low-fi wireframes for UI tickets through a configured wireframe MCP platform (Frame0, Penpot, or Figma), build a Docs Gallery page, and back-link wireframe URLs into the tickets.
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, AskUserQuestion, Agent
---

# /wireframe — UI ticket → wireframes skill

Run after `/ticket` when a feature's tickets.json has UI work that benefits from a
wireframe pass before `/develop`.

## Supported platforms

The skill is platform-agnostic at the orchestration layer. Step-00 resolves
`config.wireframes.platform` → a helper script; every later step calls the
helper via the variable `$helper`. Platform-specific behavior is isolated to
clearly labeled sections in each step.

| `wireframes.platform` | Helper                              | Surface form                                    |
|-----------------------|-------------------------------------|-------------------------------------------------|
| `frame0`              | `skills/_shared/frame0-helper.sh`   | Desktop app + MCP                               |
| `penpot`              | `skills/_shared/penpot-helper.sh`   | Web app + MCP plugin                            |
| `figma`               | `skills/_shared/figma-helper.sh`    | Figma Desktop + `figma-console-mcp` + Bridge plugin |
| `none` (absent)       | —                                   | Skill skipped                                   |

See step-00 (preflight + binding) and step-02 (page/shape/export semantics)
for the platform-specific blocks.

## When to use

- A feature has `.snap/tickets/{fid}.json` and at least one ticket touches UI
  files (heuristic in step-01).
- A wireframe platform is configured: `config.wireframes.platform ∈ {"frame0","penpot","figma"}`.
- `/define` has produced `.snap/PRDs/{fid}.md` (or remote PRD via
  `manifest.refs.prd`) so screen names + states are known.

## Pipeline

| # | Step | Purpose |
|---|------|---------|
| 00 | `step-00-init.md`    | Parse args, resolve feature, load config, resolve platform + helper, run platform-specific preflight |
| 01 | `step-01-filter.md`  | Identify UI tickets via keyword + file-extension heuristic |
| 02 | `step-02-design.md`  | Per screen: create page, add shapes, export PNG via resolved helper |
| 03 | `step-03-gallery.md` | Docs Gallery page: blob-upload PNGs, embed per screen + state |
| 04 | `step-04-link.md`    | Update each UI ticket body with `wireframe_url` + `wireframe_screen` |

## Args

```
/wireframe [--resume|-r] [--feature=NN-slug] [--dry-run]
```

- `--feature` (required if multiple): target story_id (partial-match).
- `--dry-run`: helpers return mock descriptors; no MCP calls, no PNGs written,
  no docs writes.

## Outputs

- `.snap/wireframes/{story_id}/{screen-id}-{state}.{png|svg|…}`
  (local exports — the resolved helper handles platform-specific write path;
  format from `config.wireframes.export_format`).
- Remote Docs Gallery page, recorded in
  `.snap/manifests/{story_id}.manifest.json` at `.refs.wireframes_gallery`
  (`platform`, `url`, `page_id`, `synced_at`, `sync_status: "synced"`); staging
  `wireframes-gallery.md` is trashed after ack.
- Each UI ticket in `.snap/tickets/{story_id}.json` gains `wireframe_screen`
  + `wireframe_url`.
- Manifest `state` advances `ticketed` → `wireframed`.

## Resume protocol

Same pattern as `/define` and `/ticket`: `/wireframe --resume` delegates to
`progress.sh resume --skill=wireframe --story-id=…`.

## Acceptance check

- Every UI ticket flagged in step-01 has a `wireframe_url` populated in
  `.snap/tickets/{story_id}.json`.
- `manifest.refs.wireframes_gallery.sync_status = "synced"` (or step-03 skipped
  if `documentation.platform = "none"`).
- Manifest `state = "wireframed"`.
