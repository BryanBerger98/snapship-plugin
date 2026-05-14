---
name: design
description: Generate hi-fi mockups for a ticket (or every UI ticket of a feature) through a configured design platform (Penpot or Figma). Optional, parallel or sequential to /wireframe.
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, AskUserQuestion
---

# /design — hi-fi mockup skill

Run optionally — `/design` is parallel or sequential to `/wireframe`. It does
**one thing**: produce hi-fi mockups for what a ticket asks for.

Input mirrors `/develop` and `/qa`:

| Input          | Effect                                                       |
|----------------|--------------------------------------------------------------|
| `<ticket-id>`  | Mock up the single ticket.                                   |
| `<feature-id>` | Mock up every UI ticket of the feature (batch).              |

The design system is **never created or modified** by `/design`. If a DS file
is configured it may be read for component references (opt-in, see
`mode_defaults.design_system_source`) — the DS is managed outside this skill.

## Supported platforms

| `design.platform` | Helper                              | Backend                                              |
|-------------------|-------------------------------------|------------------------------------------------------|
| `penpot`          | `skills/_shared/penpot-helper.sh`   | Same MCP as `/wireframe penpot` — skill applies hi-fi shapes |
| `figma`           | `skills/_shared/figma-helper.sh`    | Same MCP as `/wireframe figma` — `figma-console-mcp` via Desktop Bridge plugin |
| `none` (absent)   | —                                   | Skill skipped                                        |

`frame0` is **excluded** by design — Frame0 is low-fi only. `/design figma`
uses the exact same helper and Desktop Bridge plugin as `/wireframe figma`.

## When to use

- A feature has `tickets.json` with at least one UI ticket.
- A design platform is configured:
  `config.design.platform ∈ {"penpot","figma"}`.

## Pipeline

| # | Step | Purpose |
|---|------|---------|
| 00 | `step-00-init.md`           | Parse args, resolve ticket/feature scope, load `config.design`, platform preflight, auto-link wireframes binding if platforms match |
| 01 | `step-01-source-resolve.md` | Build the screen×state list from the target ticket(s); detect reusable wireframes |
| 02 | `step-02-mockup.md`         | Per screen×state: frame, apply shapes/components, export asset |
| 03 | `step-03-gallery.md`        | Docs `design-gallery` page (separate from `wireframes-gallery`) |
| 04 | `step-04-link.md`           | tickets[] gain `design_url` + `design_screen` + `design_mode` |

## Args

```
/design <ticket-id|feature-id> [--resume|-r] [--dry-run] [--no-wireframe-reuse]
```

- `<ticket-id|feature-id>` (required unless `--resume`): partial-match. A
  ticket id scopes to one ticket; a feature id batches all UI tickets.
- `--dry-run`: helpers return mock descriptors; no MCP calls, no assets
  written, no docs writes.
- `--no-wireframe-reuse`: skip the "reuse `/wireframe` screens" prompt; always
  rebuild the screen list from the ticket(s).

## Outputs

- `.claude/product/features/{feature_id}/design/{screen-id}-{state}.{fmt}`
  (local cache).
- Docs `design-gallery` page (URL cached in `.docs-cache.json` under
  `design_gallery.{feature_id}`).
- Each targeted UI ticket in `tickets.json` gains `design_screen`,
  `design_url`, `design_mode` (`mockup|reused`).

## Auto-link to /wireframe

If `wireframes.platform == design.platform` **and** a wireframes binding
exists **and** `design.{platform}.{file_id|file_key}` is null → `step-00`
raises `AskUserQuestion`:

- **Yes, reuse the wireframes file** → copies binding to `design.{platform}`
- **No, separate file** → prompts for `design.{platform}` binding
- **Save to config** → persists choice for future runs

## Resume protocol

Same pattern as `/wireframe`: `/design --resume` delegates to
`resume-state.sh next --skill=design` (scope-aware state).

## Acceptance check

- Every targeted UI ticket has `design_url` set in `tickets.json`.
- `design-gallery.md` exists at `.claude/product/design-gallery.md` with one
  section per screen.
