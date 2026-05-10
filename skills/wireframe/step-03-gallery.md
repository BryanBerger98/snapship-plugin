---
step: 03-gallery
next_step: 04-link
description: AFFiNE Gallery page — render wireframes-gallery.md, blob-upload PNGs, embed per screen×state.
---

# step-03 — gallery

Build a single AFFiNE / Notion page that hosts every wireframe with section
headings per screen and image rows per state. Optional — skipped if
`documentation.platform = "none"`.

## Tasks

### A. Skip on platform=none

Read platform deterministically from the resolved config (NEVER from the user
`snapship.config.json` directly):

```bash
PLATFORM=$(jq -r '.documentation.platform // "none"' .claude/product/.config-resolved.json)
echo "documentation.platform=${PLATFORM}"
```

If `$PLATFORM = "none"`, render the local `wireframes-gallery.md` file only and
mark progress `skip` for the publish leg. Do not call docs-adapter.

If `$PLATFORM ∈ {"affine", "notion"}`, continue. Do not assume `none` on missing
field — abort with explicit error.

### B. Render the gallery markdown

Use `render-template.sh` against `templates/docs-defaults/wireframes-gallery.md`:

```bash
ctx=$(jq -n \
  --arg fid "$feature_id" \
  --arg ftitle "$feature_title" \
  --argjson screens "$(jq '.screens' .claude/product/features/${feature_id}/.wireframes-draft.json)" \
  '{feature_id:$fid, feature_title:$ftitle, screens:$screens}')

bash skills/_shared/render-template.sh \
  --template=skills/_shared/templates/docs-defaults/wireframes-gallery.md \
  --vars="$ctx" \
  > .claude/product/wireframes-gallery.md
```

### C. Upload PNGs as blobs

For each cached PNG, upload via `docs-adapter.sh` using the platform's blob
upload action (AFFiNE: `attach-blob`; Notion: file upload). Capture the returned
`blob_url` and replace the local `png_path` in the rendered markdown with the
remote URL before publishing.

```bash
bash skills/_shared/docs-adapter.sh \
  --action=upload-blob \
  --project-root="$PWD" \
  --file-path="$png_path"
# exits 10 (MCP descriptor) → call MCP tool → capture blob_url
```

### D. Push the gallery page

```bash
bash skills/_shared/docs-adapter.sh \
  --action=create \
  --project-root="$PWD" \
  --parent-id="$(jq -r .prd_global.page_id .claude/product/.docs-cache.json)" \
  --title="Wireframes — $feature_title" \
  --content-file=.claude/product/wireframes-gallery.md
```

Capture `page_id` + `url`; cache in `.docs-cache.json` under
`wireframes_gallery.${feature_id}`.

### E. Telemetry + progress

```bash
bash skills/_shared/telemetry.sh emit \
  --project-root="$PWD" --skill=wireframe --status=ok \
  --extra='{"screens_count":'"$count"'}'

bash skills/_shared/update-progress.sh \
  --project-root="$PWD" --feature-id="$feature_id" \
  --step-num=03 --step-name=gallery --status=ok --skill=wireframe
```

## Failure handling

- Blob upload rejection (size > limit, format not allowed): downscale via `sips`
  or convert via `ffmpeg` (whichever is available) and retry once. Second
  failure → mark progress `fail`, surface the file name + size.
- Page already exists (idempotent re-run): update via `--action=update` instead.
  Detect via `.docs-cache.json` lookup.

## Acceptance check

- Local `wireframes-gallery.md` exists with one section per screen and a row per
  state.
- If platform ≠ "none": gallery page URL cached in `.docs-cache.json`.

## Next step

→ `step-04-link.md`
