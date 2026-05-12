---
name: design
description: Generate hi-fi design assets (mockups, design-system bootstrap, design-system updates) for a feature through a configured design platform (Penpot or Figma). Optional, parallel or sequential to /wireframe.
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, AskUserQuestion
---

# /design — hi-fi design skill

Run optionally — `/design` is parallel or sequential to `/wireframe`. Three
modes share the same skill scaffold:

| Mode         | Purpose                                                                                   | Typical trigger                      |
|--------------|-------------------------------------------------------------------------------------------|--------------------------------------|
| `ds-init`    | Bootstrap a design system file from `_shared/templates/design-system-defaults/*.yaml`     | First run, no DS file configured     |
| `ds-update`  | Diff design-system specs vs current file → patch in place                                 | Specs changed, DS file out of date   |
| `mockup`     | Per screen×state: hi-fi mockup applying DS components, export asset, link to tickets      | After `/ticket` (and optionally `/wireframe`) |

`step-00` resolves the mode automatically (or asks via `AskUserQuestion` if
ambiguous).

## Supported platforms

| `design.platform` | Helper                                  | Backend                                                                     |
|-------------------|-----------------------------------------|-----------------------------------------------------------------------------|
| `penpot`          | `skills/_shared/penpot-helper.sh`       | Same MCP as `/wireframe penpot` — skill applies hi-fi components            |
| `figma`           | `skills/_shared/figma-bridge-helper.sh` | `bridge-ds compile` (YAML CSpec → JS) + transport `official` (`figma_execute`) or `console` (paste DevTools) |
| `none` (absent)   | —                                       | Skill skipped                                                               |

`frame0` is **excluded** by design — Frame0 is low-fi only.

## When to use

- A feature has `tickets.json` (mockup mode) **or** a DS bootstrap/update is
  needed (ds-* modes).
- A design platform is configured:
  `config.design.platform ∈ {"penpot","figma"}`.

## Pipeline

| # | Step | Purpose |
|---|------|---------|
| 00 | `step-00-init.md`           | Parse args, resolve feature+mode, load `config.design`, platform preflight, auto-link wireframes binding if platforms match |
| 01 | `step-01-ds-bootstrap.md`   | Modes `ds-init` / `ds-update` only — Bridge-compile DS YAML → push/patch the DS file |
| 02 | `step-02-source-resolve.md` | Mode `mockup` only — detect existing wireframes (`wireframes_url`) or fall back to tickets-only source |
| 03 | `step-03-mockup.md`         | Mode `mockup` only — per screen×state: frame, components, export asset |
| 04 | `step-04-gallery.md`        | Mode `mockup` only — Docs `design-gallery` page (separate from `wireframes-gallery`) |
| 05 | `step-05-link.md`           | Mode `mockup` only — tickets[] gain `design_url` + `design_screen` + `design_mode` |

`ds-init` / `ds-update` runs stop after step-01.

## Args

```
/design [--resume|-r] [--feature=NN-slug] [--mode=ds-init|ds-update|mockup] [--dry-run]
```

- `--feature` (required for `mockup` if multiple features): target feature_id (partial-match).
- `--mode` (optional): force a mode. Auto-resolved by step-00 if absent.
- `--dry-run`: helpers return mock descriptors; no MCP calls, no assets written, no docs writes.

## Outputs

- **`ds-init`** — DS file populated with atomic/molecular/organism components.
  Path/id cached in `config.design.{platform}.{file_id|file_key}` if "Save to
  config" chosen.
- **`ds-update`** — DS file patched in place. Diff summary cached in
  `.design-cache.json`.
- **`mockup`**:
  - `.claude/product/features/{feature_id}/design/{screen-id}-{state}.{fmt}`
    (local cache).
  - Docs `design-gallery` page (URL cached in `.docs-cache.json` under
    `design_gallery.{feature_id}`).
  - Each UI ticket in `tickets.json` gains `design_screen`, `design_url`,
    `design_mode` (`mockup|reused`).

## Auto-link to /wireframe

If `wireframes.platform == design.platform` **and** wireframes binding exists
**and** `design.{platform}.{file_id|file_key}` is null → `step-00` raises
`AskUserQuestion`:

- **Yes, reuse the wireframes file** → copies binding to `design.{platform}`
- **No, separate file** → prompts for `design.{platform}` binding
- **Save to config** → persists choice for future runs

## Resume protocol

Same pattern as `/define`, `/ticket`, `/wireframe`: `/design --resume`
delegates to `resume-state.sh next --skill=design` (mode-aware state).

## Acceptance check

- **`ds-init`**: DS file populated, file id/key cached.
- **`ds-update`**: DS file patched, diff summary cached.
- **`mockup`**: every UI ticket flagged in step-02 has `design_url`,
  `design-gallery.md` exists at `.claude/product/design-gallery.md` with
  one section per screen.
