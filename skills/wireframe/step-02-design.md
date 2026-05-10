---
step: 02-design
next_step: 03-gallery
description: Frame0 MCP loop — per screen×state, create page, add shapes, export PNG to local cache.
---

# step-02 — design

Generate the actual wireframes. One Frame0 page per `(screen_id, state)`.

## Per-screen loop

For each screen draft from step-01, and for each state in `states[]`:

1. **Create page**: the title doubles as the Frame0 export filename basename
   (Frame0 exports as `<page_title>.<ext>` into `wireframes.export_source_dir`,
   default `~/Downloads`). Prefix with `feature_slug` to keep filenames unique
   across features in the user's Downloads:
   ```bash
   page_title="${feature_slug}-${screen_id}-${state}"
   bash skills/_shared/frame0-helper.sh create-page \
     --title="$page_title" \
     --project-root="$PWD"
   # exits 10 with descriptor → invoke MCP, capture page_id
   ```

2. **Compose shapes**: build a JSON array of low-fi shapes representing the
   screen state. The model picks shape types appropriate to `screen_hint`:
   - `signup-screen` → 1× heading, 2× input, 1× button, 1× link.
   - `dashboard` → 1× nav, 3-4× card, 1× empty-state placeholder.

   Use the screen IDs from step-01 + states `(empty | filled | error | loading)`
   as cues. Rely on the model's reasoning — do not hard-code a shape library.

   ```bash
   bash skills/_shared/frame0-helper.sh add-shapes \
     --page-id="$page_id" \
     --shapes-file=".tmp/shapes-${screen_id}-${state}.json" \
     --project-root="$PWD"
   ```

3. **Export PNG** (Frame0 writes to `wireframes.export_source_dir`, NOT to
   `--output-path` — the `output-path` param is informational, ignored by the
   Frame0 MCP):
   ```bash
   bash skills/_shared/frame0-helper.sh export-page \
     --page-id="$page_id" \
     --output-path=".claude/product/features/${feature_id}/wireframes/${page_title}.png" \
     --format=png \
     --scale=2 \
     --project-root="$PWD"
   # exits 10 with descriptor → invoke MCP, Frame0 writes to ${export_source_dir}/${page_title}.png
   ```

4. **Move export into the project** (Frame0 always writes to a single OS
   directory — typically `~/Downloads` — regardless of MCP params. The skill
   moves the file from there into `.claude/product/features/<id>/wireframes/`,
   leaving Downloads clean):
   ```bash
   bash skills/_shared/frame0-helper.sh move-export \
     --filename="${page_title}.png" \
     --output-path=".claude/product/features/${feature_id}/wireframes/${page_title}.png" \
     --project-root="$PWD"
   # local-only — never emits an MCP descriptor; exit 0 on success, 1 if source missing.
   ```

5. **Cache descriptor result**: append to `.wireframes-draft.json`:
   ```json
   {
     "screens": [
       {
         "screen_id": "signup-screen",
         "pages": [
           {"state": "empty",  "frame0_page_id": "...", "png_path": "..."},
           {"state": "filled", "frame0_page_id": "...", "png_path": "..."}
         ]
       }
     ]
   }
   ```

## Parallelism

Frame0 MCP creates pages serially (page IDs cascade in some setups). Do **not**
parallelise across screens — issue calls one at a time and wait for each
descriptor result. Within a screen, all states share the same page family but
separate pages.

## Dry-run

`--dry-run` writes a placeholder PNG (1×1 transparent) and uses fake page IDs
(`frame0_page_id: "DRY-{n}"`). `move-export --dry-run` returns
`{moved: false}` without touching the filesystem. This lets the rest of the
pipeline (gallery + link) be tested without burning Frame0 quota.

## Failure handling

- Frame0 MCP timeout / 5xx → retry once with 5s backoff. Second failure → mark
  progress `fail` and stop. The cached pages from earlier screens persist; resume
  picks up from the unprocessed screen.
- Shape JSON rejected by Frame0 (invalid schema) → log the error verbatim with
  the screen_id, mark progress `fail`.

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
- `frame0_page_id` is set (or `DRY-…` in dry-run).

## Next step

→ `step-03-gallery.md`
