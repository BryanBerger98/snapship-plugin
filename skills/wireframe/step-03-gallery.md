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
PLATFORM=$(jq -r '.documentation.platform // "none"' <<<"$CONFIG_JSON")
echo "documentation.platform=${PLATFORM}"
```

If `$PLATFORM = "none"`, render the local `wireframes-gallery.md` file only and
mark progress `skip` for the publish leg. Do not call docs-adapter.

If `$PLATFORM ∈ {"affine", "notion"}`, continue. Do not assume `none` on missing
field — abort with explicit error.

### B. Render the gallery markdown

Resolve the staging path via `sync-push.sh`, render with `render-template.sh`
against `templates/docs-defaults/wireframes-gallery.md`:

```bash
STAGING=$(bash skills/_shared/sync-push.sh staging-path \
  --project-root="$PWD" \
  --feature-id="$feature_id" \
  --kind=wireframes-gallery)

ctx=$(jq -n \
  --arg fid "$feature_id" \
  --arg ftitle "$feature_title" \
  --argjson screens "$(jq '.screens' .snap/wireframes/${feature_id}.draft.json)" \
  '{feature_id:$fid, feature_title:$ftitle, screens:$screens}')

bash skills/_shared/render-template.sh \
  --template=skills/_shared/templates/docs-defaults/wireframes-gallery.md \
  --vars="$ctx" \
  > "$STAGING"
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

Parent page = the feature PRD page recorded in
`.snap/manifests/${feature_id}.manifest.json` at `.refs.prd.page_id`:

```bash
PRD_PAGE_ID=$(jq -r '.refs.prd.page_id // ""' \
  ".snap/manifests/${feature_id}.manifest.json")

create_out=$(bash skills/_shared/docs-adapter.sh \
  --action=create \
  --project-root="$PWD" \
  --parent-id="$PRD_PAGE_ID" \
  --title="Wireframes — $feature_title" \
  --content-file="$STAGING")
# Parse {page_id, url} from create_out.
GALLERY_PAGE_ID=$(jq -r '.page_id' <<<"$create_out")
GALLERY_URL=$(jq -r '.url' <<<"$create_out")
```

### E. Ack into manifest.refs.wireframes_gallery

```bash
bash skills/_shared/sync-push.sh ack \
  --project-root="$PWD" \
  --feature-id="$feature_id" \
  --kind=wireframes-gallery \
  --platform="$PLATFORM" \
  --url="$GALLERY_URL" \
  --page-id="$GALLERY_PAGE_ID"
```

`sync-push.sh ack` updates `manifest.refs.wireframes_gallery` and trashes the
staging file.

### F. Telemetry + progress

```bash
bash skills/_shared/telemetry.sh log \
  --project-root="$PWD" --skill=wireframe \
  --step-num=03 --step-name=gallery --status=ok \
  --extra='{"screens_count":'"$count"'}'

bash skills/_shared/progress.sh step \
  --project-root="$PWD" \
  --skill=wireframe \
  --feature-id="$feature_id" \
  --step-num=03 \
  --step-name=gallery \
  --status=ok
```

## Failure handling

- Blob upload rejection (size > limit, format not allowed): downscale via `sips`
  or convert via `ffmpeg` (whichever is available) and retry once. Second
  failure → mark progress `fail`, surface the file name + size.
- Page already exists (idempotent re-run): if `manifest.refs.wireframes_gallery`
  already has a `page_id`, call `--action=update` against that page_id instead
  of `create`.

## Acceptance check

- Staging `wireframes-gallery.md` rendered with one section per screen and a
  row per state.
- If platform ≠ "none": `manifest.refs.wireframes_gallery.sync_status = "synced"`
  with `url` + `page_id` populated; staging file trashed.

## Next step

→ `step-04-link.md`
