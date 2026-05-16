---
step: 02-mockup
next_step: 03-gallery
description: Per screen×state — create a page, compose hi-fi shapes, export ONE asset (format from config) via the configured design platform (penpot | figma).
---

# step-02 — mockup

Generate hi-fi mockups. One page per `(screen_id, state)`. **Exactly one
export per page** in the format declared by `design.export_format`.

The skill picks the helper based on `design.platform` resolved at step-00 —
the same two helpers `/wireframe` uses, minus `frame0`:

| Platform | Helper                            | Export mechanism                                              |
|----------|-----------------------------------|---------------------------------------------------------------|
| `penpot` | `skills/_shared/penpot-helper.sh` | `export_shape` MCP tool writes the file directly              |
| `figma`  | `skills/_shared/figma-helper.sh`  | `figma_execute` returns base64 inline → `save-export` decodes |

Below, `$helper` is the resolved helper path. Both helpers expose the same
action surface (`create-page`, `add-shapes`, `export-png`, `save-export`) so
the loop is platform-agnostic — only the export step differs. Helpers are
context-agnostic: pass resolved config values (`$ds_file_id`,
`$ds_file_key`, `$export_format`, …) explicitly — step-00 already resolved
them and persisted them to skill state.

## Resolve export format (once)

```bash
fmt="$export_format" # from skill state (resolved at step-00)
canvas=$(jq -r '.design.mode_defaults.mockup_canvas // "mobile-portrait"' <<<"$CONFIG_JSON")
```

`$fmt` is the **sole source of truth** for the output extension and helper
format. Do not hardcode `png`. Do not call `export-png` more than once per
page.

## Optional design-system read

`ds_source` (resolved at step-00 from `design.mode_defaults.design_system_source`):

| `ds_source` | Behaviour                                                                                       |
|-------------|-------------------------------------------------------------------------------------------------|
| `none`      | Free hi-fi mockup — no DS lookup.                                                               |
| `file`      | Read-only: inspect the configured DS file/page for component names, tokens, colours, spacing, and mirror them in the composed shapes. |
| `auto`      | `file` if a DS binding is configured and reachable, else `none`.                                |

`/design` **never** writes to the DS file. The read is purely a visual
reference — for penpot, list the `design_system_page`; for figma, the model
may call `figma-helper.sh --action=get-page` on a DS page. The DS itself is
managed outside this skill.

## Per-screen loop

For each screen in `.snap/designs/${story_id}.draft.json`, for each state in `states[]`:

### 1. Create page

```bash
page_title="${story_slug}-${screen_id}-${state}"
bash "$helper" create-page \
  --title="$page_title" \
  --project-root="$PWD"
# exit 10 with descriptor → invoke MCP tool, capture page_id
```

### 2. Compose shapes

Build a JSON array of **hi-fi** shapes representing the screen state — real
colours, typography, spacing, component-accurate layout. Drive content from
**what the ticket asks for** (title, description, acceptance criteria). If
`ds_source` resolved to `file`, mirror the DS component names, tokens and
colours read above.

Shape schema (shared across platforms — helpers normalize internally):
```json
{"type":"text|rect|ellipse|line","name":"...","x":N,"y":N,"width":N,"height":N,"text":"...","fill":"#hex"}
```

```bash
bash "$helper" add-shapes \
  --page-id="$page_id" \
  --shapes-file=".tmp/shapes-${screen_id}-${state}.json" \
  --project-root="$PWD"
```

### 3. Export asset

Invoke `export-png` **once** with the resolved `$fmt`.

#### 3.a — penpot

The Penpot MCP `export_shape` tool accepts an absolute `filePath` and writes
the asset itself. Output path must be absolute. Supported `$fmt`: `png|svg`.
```bash
target="$PWD/.snap/designs/${story_id}/${page_title}.${fmt}"
bash "$helper" export-png \
  --page-id="$page_id" \
  --output-path="$target" \
  --format="$fmt" \
  --file-id="$ds_file_id"
# exits 10 with descriptor; after MCP runs, the file exists at $target.
```

#### 3.b — figma

The Figma helper emits a `figma_execute` descriptor whose JS calls
`node.exportAsync(...)` and returns base64 inline; `save-export` decodes it
to disk. Supported `$fmt`: `png|svg|jpg|pdf`. Default scale is `2`.
```bash
target=".snap/designs/${story_id}/${page_title}.${fmt}"

# Step 1: emit figma_execute descriptor (exit 10), MCP returns base64.
exec_result=$(bash "$helper" export-png \
  --shape-id="$page_id" \
  --output-path="$target" \
  --format="$fmt" \
  --scale=2 \
  --file-key="$ds_file_key")
# → dispatcher invokes figma_execute, captures result.data (base64 string).

# Step 2: decode locally to disk.
bash "$helper" save-export \
  --output-path="$target" \
  --base64-data="$exec_data"
# exit 0 on success ({written:true,bytes:N}).
```

### 4. Cache descriptor

Append to `.snap/designs/${story_id}.draft.json`:

```json
{
  "screens": [
    {
      "screen_id": "signup-screen",
      "pages": [
        {"state":"default", "platform_page_id":"...", "asset_path":"...","mode":"mockup"},
        {"state":"error",   "platform_page_id":"...", "asset_path":"...","mode":"mockup"}
      ]
    }
  ]
}
```

If the reuse decision at step-01 set a screen as "reused" (existing wireframe
asset reapplied without re-mocking), set `mode: "reused"` and leave
`asset_path` pointing to the wireframe png.

## Parallelism

Same constraint as `/wireframe`: serial within a feature. Penpot's plugin
context is single-tab; Figma Desktop runs a single active file. Issue calls
one at a time.

## Dry-run

`--dry-run` makes both helpers return mock descriptors (`DRY-{n}`),
`written:false`. No MCP calls. No assets written.

## Failure handling

Generic:
- MCP timeout / 5xx → retry once with 5s backoff. Second failure → mark
  progress `fail`. Cached pages from earlier screens persist.

Platform-specific:
- **penpot** — `export_shape` requires an absolute filePath and the target
  shape must exist on the active page. If the user navigated away in the
  Penpot browser tab mid-run, the next call surfaces "No plugin connected" —
  re-bind in the Penpot UI and resume.
- **figma** — `figma_execute` failures usually mean the Desktop Bridge plugin
  disconnected (Figma Desktop closed, plugin disabled, or WebSocket port
  range 9223–9232 blocked). Re-enable the plugin (Plugins → Browse →
  "Desktop Bridge" → Open) and resume. If `save-export` fails with "no
  base64 data", the previous `figma_execute` returned an error payload —
  inspect the MCP transcript before retrying.

## Append progress

```bash
bash skills/_shared/progress.sh step \
  --project-root="$PWD" \
  --skill=design \
  --story-id="$story_id" \
  --step-num=02 \
  --step-name=mockup \
  --status=ok
```

## Acceptance check

- Every `(screen_id, state)` pair has an `asset_path` that exists on disk.
- `platform_page_id` is set (or `DRY-…` in dry-run).
- `mode` set to `mockup` (new) or `reused` (linked to existing wireframe).

## Next step

→ `step-03-gallery.md`
