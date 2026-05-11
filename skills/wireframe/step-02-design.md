---
step: 02-design
next_step: 03-gallery
description: Per screen×state, create page, add shapes, export PNG via the configured wireframe platform (frame0 | penpot).
---

# step-02 — design

Generate the actual wireframes. One page per `(screen_id, state)`.

The skill picks the helper based on `config.wireframes.platform` resolved in
step-00:

| Platform | Helper script                                  | Export mechanism                                 |
|----------|------------------------------------------------|--------------------------------------------------|
| `frame0` | `skills/_shared/frame0-helper.sh`              | HTTP API bypass (`export-png`) — local decode    |
| `penpot` | `skills/_shared/penpot-helper.sh`              | `export_shape` MCP tool writes file directly     |

Below, `$helper` is the resolved helper path. Both helpers expose the same
action surface (`create-page`, `add-shapes`, `export-png`) so the loop below
is platform-agnostic — only the `export-png` call differs slightly.

## Per-screen loop

For each screen draft from step-01, and for each state in `states[]`:

1. **Create page**: title encodes feature + screen + state so the resulting
   PNG filename stays unique and self-describing:
   ```bash
   page_title="${feature_slug}-${screen_id}-${state}"
   bash "$helper" create-page \
     --title="$page_title" \
     --project-root="$PWD"
   # exits 10 with descriptor → invoke MCP tool, capture page_id
   ```

2. **Compose shapes**: build a JSON array of low-fi shapes representing the
   screen state. The model picks shape types appropriate to `screen_hint`:
   - `signup-screen` → 1× heading, 2× input, 1× button, 1× link.
   - `dashboard` → 1× nav, 3-4× card, 1× empty-state placeholder.

   Shape schema (shared across platforms — helpers normalize internally):
   ```json
   {"type":"text|rect|ellipse","name":"...","x":N,"y":N,"width":N,"height":N,"text":"...","fill":"#hex"}
   ```

   ```bash
   bash "$helper" add-shapes \
     --page-id="$page_id" \
     --shapes-file=".tmp/shapes-${screen_id}-${state}.json" \
     --project-root="$PWD"
   ```

3. **Export PNG**:

   **frame0** — bypasses MCP, POSTs `file:export-image` to Frame0 desktop's
   HTTP API and decodes the base64 locally:
   ```bash
   target=".claude/product/features/${feature_id}/wireframes/${page_title}.png"
   bash "$helper" export-png \
     --page-id="$page_id" \
     --output-path="$target" \
     --format=png \
     --project-root="$PWD"
   # exit 0 on success ({written:true,bytes:N}), 1 if desktop unreachable.
   ```
   Override port via `--api-port=N` or `wireframes.frame0_api_port`.

   **penpot** — the Penpot MCP `export_shape` tool accepts an absolute
   `filePath` and writes the asset itself. The helper just emits the
   descriptor; the dispatcher invokes the MCP tool. Output path must be
   absolute:
   ```bash
   target="$PWD/.claude/product/features/${feature_id}/wireframes/${page_title}.png"
   bash "$helper" export-png \
     --page-id="$page_id" \
     --output-path="$target" \
     --format=png \
     --project-root="$PWD"
   # exits 10 with descriptor; after MCP runs, the file exists at $target.
   ```
   Format enum is `png|svg` for penpot (no `jpeg`/`webp`/`pdf`).

4. **Cache descriptor result**: append to `.wireframes-draft.json`:
   ```json
   {
     "screens": [
       {
         "screen_id": "signup-screen",
         "pages": [
           {"state": "empty",  "platform_page_id": "...", "png_path": "..."},
           {"state": "filled", "platform_page_id": "...", "png_path": "..."}
         ]
       }
     ]
   }
   ```

## Parallelism

Both Frame0 and Penpot MCP create pages serially in practice (Penpot's plugin
context shares storage between calls). Do **not** parallelise across screens —
issue calls one at a time and wait for each descriptor result. Within a screen,
all states share the same page family but separate pages.

## Dry-run

`--dry-run` makes both helpers return mock descriptors with fake page IDs
(`DRY-{n}`) and `written:false`. No MCP calls. No PNGs written. Lets the rest
of the pipeline (gallery + link) be tested without a running design tool.

## Failure handling

- MCP timeout / 5xx → retry once with 5s backoff. Second failure → mark
  progress `fail` and stop. Cached pages from earlier screens persist; resume
  picks up from the unprocessed screen.
- Shape JSON rejected by the MCP server → log the error verbatim with the
  screen_id, mark progress `fail`.
- **Penpot specifics**: `export_shape` requires an absolute filePath and the
  target shape must exist on the active page — verify `page_id` is current
  before exporting (the helper's add-shapes JS calls `penpot.openPage()`).

## Append progress

```bash
bash skills/_shared/update-progress.sh \
  --project-root="$PWD" \
  --feature-id="$feature_id" \
  --step-num=02 \
  --step-name=design \
  --status=ok \
  --skill=wireframe
```

## Acceptance check

- Every `(screen_id, state)` pair has a `png_path` that exists on disk.
- `platform_page_id` is set (or `DRY-…` in dry-run).

## Next step

→ `step-03-gallery.md`
