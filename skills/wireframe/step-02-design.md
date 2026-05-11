---
step: 02-design
next_step: 03-gallery
description: Frame0 MCP loop — per screen×state, create page, add shapes, export PNG to local cache.
---

# step-02 — design

Generate the actual wireframes. One Frame0 page per `(screen_id, state)`.

## Per-screen loop

For each screen draft from step-01, and for each state in `states[]`:

1. **Create page**: title encodes feature + screen + state so the resulting
   PNG filename stays unique and self-describing:
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

3. **Export PNG** (Frame0 MCP returns the image as a **base64 string** in the
   tool result — it does NOT write a file. The `--output-path` arg is the
   target the next step will use, not a path Frame0 itself honours):
   ```bash
   target=".claude/product/features/${feature_id}/wireframes/${page_title}.png"
   bash skills/_shared/frame0-helper.sh export-page \
     --page-id="$page_id" \
     --output-path="$target" \
     --format=png \
     --scale=2 \
     --project-root="$PWD"
   # exits 10 with descriptor → invoke MCP, capture base64 from the result
   ```

4. **Decode base64 → PNG** (`save-export` is local-only — never emits an MCP
   descriptor; writes the binary asset named after the page = feature+screen+state):
   ```bash
   bash skills/_shared/frame0-helper.sh save-export \
     --output-path="$target" \
     --base64-file=".tmp/frame0-${page_title}.b64" \
     --project-root="$PWD"
   # OR pipe the base64 directly:
   #   printf '%s' "$b64" | bash skills/_shared/frame0-helper.sh save-export \
   #     --output-path="$target" --base64-stdin
   # exit 0 on success, 1 if decode fails / payload empty.
   ```

   The helper strips a `data:image/...;base64,` prefix if Frame0 includes one,
   trims whitespace, and `mkdir -p`'s the target directory.

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
(`frame0_page_id: "DRY-{n}"`). `save-export --dry-run` returns
`{written: false, base64_chars: N}` without touching the filesystem. This lets
the rest of the pipeline (gallery + link) be tested without burning Frame0 quota.

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
