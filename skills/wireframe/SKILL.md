---
name: wireframe
description: Generate low-fi wireframes for UI tickets via Frame0 or Penpot MCP, build an AFFiNE Gallery page, and back-link wireframe URLs into the tickets.
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, AskUserQuestion
---

# /wireframe — UI ticket → wireframes skill

Run after `/ticket` when a feature's tickets.json has UI work that benefits from a
wireframe pass before `/develop`.

## When to use

- A feature has `tickets.json` and at least one ticket touches UI files (heuristic
  in step-01).
- Wireframe platform is configured: `config.wireframes.platform = "frame0"` or `"penpot"`.
- `/define` has populated `prd-feature.md` so screen names + states are known.

## Pipeline

| # | Step | Purpose |
|---|------|---------|
| 00 | `step-00-init.md`    | Parse args, resolve feature, load tickets.json + config |
| 01 | `step-01-filter.md`  | Identify UI tickets via keyword + file-extension heuristic |
| 02 | `step-02-design.md`  | Frame0 or Penpot MCP: per screen create page, add shapes, export PNG |
| 03 | `step-03-gallery.md` | AFFiNE Gallery page: blob-upload PNGs, embed per screen + state |
| 04 | `step-04-link.md`    | Update each UI ticket body with `wireframe_url` + `wireframe_screen` |

## Args

```
/wireframe [--resume|-r] [--feature=NN-slug] [--dry-run]
```

- `--feature` (required if multiple): target feature_id (partial-match).
- `--dry-run`: render shapes locally and skip Frame0 / AFFiNE writes.

## Outputs

- `.claude/product/features/{feature_id}/wireframes/{screen-id}-{state}.png` (local
  cache — frame0 decodes base64 locally; penpot writes file directly via MCP).
- AFFiNE Gallery page (URL cached in `.docs-cache.json` under
  `wireframes_gallery.url`).
- Each UI ticket in `tickets.json` gains `wireframe_screen` + `wireframe_url`.

## Resume protocol

Same pattern as `/define` and `/ticket`: `/wireframe --resume` delegates to
`resume-state.sh next --skill=wireframe`.

## Acceptance check

- Every UI ticket flagged in step-01 has a `wireframe_url` populated in
  `tickets.json`.
- `wireframes-gallery.md` exists at `.claude/product/wireframes-gallery.md` with
  one section per screen.
