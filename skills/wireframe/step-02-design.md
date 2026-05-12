---
step: 02-design
next_step: 03-gallery
description: Per screen×state, create page, add shapes, export ONE asset (format from config) via the configured wireframe platform (frame0 | penpot).
---

# step-02 — design

Generate the actual wireframes. One page per `(screen_id, state)`. **Exactly
one export per page** in the format declared by `config.wireframes.export_format`
(single-value enum — never run the export action twice to produce alternate
formats).

The skill picks the helper based on `config.wireframes.platform` resolved in
step-00:

| Platform | Helper script                                  | Export mechanism                                 |
|----------|------------------------------------------------|--------------------------------------------------|
| `frame0` | `skills/_shared/frame0-helper.sh`              | HTTP API bypass (`export-png`) — local decode    |
| `penpot` | `skills/_shared/penpot-helper.sh`              | `export_shape` MCP tool writes file directly     |

Below, `$helper` is the resolved helper path. Both helpers expose the same
action surface (`create-page`, `add-shapes`, `export-png`) so the loop below
is platform-agnostic — only the `export-png` call differs slightly.

## Resolve export format (once, at start of step)

```bash
fmt=$(jq -r '.wireframes.export_format // "png"' .claude/product/.config-resolved.json)
# fmt ∈ {png, svg, pdf} per config schema; helpers validate per-platform support.
```

`$fmt` is the **sole source of truth** for the output extension and helper
format. Do not hardcode `png` in filenames or `--format` flags. Do not call
`export-png` more than once per page.

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

3. **Export** — invoke the helper's `export-png` action **once** with the
   format resolved above. The action name is historical; it handles whatever
   `$fmt` resolves to (helpers validate per-platform support and exit 2 if
   the format is unsupported on the active platform).

   ### 3.a — frame0

   The helper bypasses MCP, POSTs `file:export-image` to Frame0 desktop's
   HTTP API and decodes the base64 locally. Output path may be relative.
   Supported `$fmt` values: `png|jpeg|webp` (Frame0's HTTP API surface — no
   `svg`/`pdf`; switch to `wireframes.platform = "penpot"` for SVG).
   ```bash
   target=".claude/product/features/${feature_id}/wireframes/${page_title}.${fmt}"
   bash "$helper" export-png \
     --page-id="$page_id" \
     --output-path="$target" \
     --project-root="$PWD"
   # exit 0 on success ({written:true,bytes:N}), 1 if desktop unreachable.
   # Format is taken from config — DO NOT pass --format here.
   ```
   Override port via `--api-port=N` or `wireframes.frame0_api_port`.

   ### 3.b — penpot

   The Penpot MCP `export_shape` tool accepts an absolute `filePath` and
   writes the asset itself. The helper emits the MCP descriptor; the
   dispatcher invokes the tool. Output path must be absolute. Supported
   `$fmt` values: `png|svg` (no `jpeg`/`webp`/`pdf`).
   ```bash
   target="$PWD/.claude/product/features/${feature_id}/wireframes/${page_title}.${fmt}"
   bash "$helper" export-png \
     --page-id="$page_id" \
     --output-path="$target" \
     --project-root="$PWD"
   # exits 10 with descriptor; after MCP runs, the file exists at $target.
   # Format is taken from config — DO NOT pass --format here.
   ```

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

Both supported platforms create pages serially in practice (Frame0 desktop has
a single active document; Penpot's plugin context shares storage between
calls). Do **not** parallelise across screens — issue calls one at a time and
wait for each descriptor result. Within a screen, all states share the same
page family but separate pages.

## Dry-run

`--dry-run` makes both helpers return mock descriptors with fake page IDs
(`DRY-{n}`) and `written:false`. No MCP calls. No PNGs written. Lets the rest
of the pipeline (gallery + link) be tested without a running design tool.

## Failure handling

Generic:
- MCP timeout / 5xx → retry once with 5s backoff. Second failure → mark
  progress `fail` and stop. Cached pages from earlier screens persist; resume
  picks up from the unprocessed screen.
- Shape JSON rejected by the MCP server → log the error verbatim with the
  screen_id, mark progress `fail`.

Platform-specific:
- **frame0** — `export-png` exit 1 means Frame0 desktop is unreachable on the
  configured HTTP port. Re-check `wireframes.frame0_api_port` and that the
  desktop app is running. Resume to retry.
- **penpot** — `export_shape` requires an absolute filePath and the target
  shape must exist on the active page. The helper's `add-shapes` JS calls
  `penpot.openPage()` so the page is current at export time. If the user
  navigated away in the browser tab mid-run, the next call surfaces "No
  plugin connected" — re-bind in the Penpot UI and resume.

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
