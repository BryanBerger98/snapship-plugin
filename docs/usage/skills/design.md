# `/snap:design` — hi-fi mockups

Generates high-fidelity mockups for what a ticket asks for, via the
configured design platform (Penpot or Figma). Builds a
`design-gallery` page in the docs and back-links the URLs into the tickets.
**Optional** — parallel or sequential to `/snap:wireframe`.

`/snap:design` does **one thing only**: mockups. It never creates or
modifies the design system. If a DS file is configured, it can be
**read** as a component reference (opt-in via `mode_defaults.design_system_source`)
— the DS is managed outside this skill.

## Input

Like `/snap:develop` and `/snap:qa`:

| Input          | Effect                                          |
| -------------- | ----------------------------------------------- |
| `<ticket-id>`  | Mocks up the single ticket.                     |
| `<feature-id>` | Mocks up every UI ticket in the feature (batch). |

Partial-match on the id. With no argument (and no `--resume`), step-00 proposes
the UI tickets with no `design_url` via `AskUserQuestion`.

## When to use it

- A feature has a `tickets.json` with at least one UI ticket.
- A design platform is configured:
  `config.design.platform ∈ {penpot, figma}`.

## Supported platforms

| `design.platform` | Helper                       | Surface                                                            |
| ----------------- | ---------------------------- | ------------------------------------------------------------------ |
| `penpot`          | `_shared/penpot-helper.sh`   | Same MCP as `/snap:wireframe penpot` — the skill applies hi-fi shapes. |
| `figma`           | `_shared/figma-helper.sh`    | Same helper and same Desktop Bridge plugin as `/snap:wireframe figma` (`figma-console-mcp`). |
| `none` (absent)   | —                            | Skill skipped.                                                     |

`frame0` is **excluded** by design: Frame0 is low-fi only.
`/snap:design figma` uses the exact same helper and the same
Desktop Bridge plugin as `/snap:wireframe figma`.

> **Figma**: requires Figma Desktop running, the Desktop Bridge plugin active, and
> a token in `.env.snap` (key `FIGMA_ACCESS_TOKEN`, override
> `design.figma.token_env`).

## Syntax

```
/snap:design <ticket-id|feature-id> [--resume|-r] [--dry-run] [--no-wireframe-reuse]
```

## Flags

| Flag                   | Effect                                                                                 |
| ---------------------- | -------------------------------------------------------------------------------------- |
| `<ticket-id\|feature-id>` | Required except with `--resume`. Ticket id → one ticket; feature id → every UI ticket. |
| `--resume` / `-r`      | Resumes via `progress.sh resume next --skill=design`.                                  |
| `--dry-run`            | Helpers return mock descriptors: no MCP calls, no assets, no doc writes.               |
| `--no-wireframe-reuse` | Skips the "reuse `/wireframe` screens" prompt; rebuilds the list from the tickets.    |

## Pipeline

| #  | Step                        | Role                                                                                 |
| -- | --------------------------- | ------------------------------------------------------------------------------------ |
| 00 | `step-00-init.md`           | Parses args, resolves ticket/feature scope, loads `config.design`, platform preflight, auto-links the wireframes binding if the platforms match. |
| 01 | `step-01-source-resolve.md` | Builds the screen × state list from the target ticket(s); detects reusable wireframes. |
| 02 | `step-02-mockup.md`         | Per screen × state: frame, applies shapes/components, exports the asset.             |
| 03 | `step-03-gallery.md`        | `design-gallery` page in the docs (separate from `wireframes-gallery`).              |
| 04 | `step-04-link.md`           | Each target ticket gains `design_url` + `design_screen` + `design_mode`.             |

## Auto-link to `/snap:wireframe`

If `wireframes.platform == design.platform` **and** a wireframes binding exists
**and** `design.{platform}.{file_id|file_key}` is null → `step-00` raises an
`AskUserQuestion`:

- **Yes, reuse the wireframes file** → copies the binding into `design.{platform}`.
- **No, separate file** → asks for the `design.{platform}` binding.
- **Save to config** → persists the choice for future runs.

## Optional DS read

`mode_defaults.design_system_source` drives the component reference in step-02:

| Value   | Effect                                                             |
| ------- | ------------------------------------------------------------------ |
| `none`  | No DS read — mockups from scratch.                                 |
| `file`  | Reads the configured DS file (`design.{platform}.design_system_page`) as a visual reference. |
| `auto`  | Reads the DS if configured, otherwise `none`.                      |

The DS is **read-only** — `/snap:design` never writes to it.

## Outputs

- `.snap/designs/{feature_id}/{screen-id}-{state}.{fmt}` (local cache pre-push).
- `design-gallery` page in the docs — ref persisted in
  `manifests/{feature_id}.manifest.json` → `refs.design_gallery.{page_id,url,synced_at,sync_status}`.
- `.snap/designs/{feature_id}/gallery.md` — one section per screen (source rendered before push).
- Each target UI ticket in `.snap/tickets/{feature_id}.json` gains
  `design_screen`, `design_url`, `design_mode` (`mockup` | `reused`).

## Next step

`/snap:develop` — its step-00 shows a designer-handoff banner if
`tickets[].design_url` is set.
