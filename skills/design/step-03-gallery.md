---
step: 03-gallery
next_step: 04-link
description: Render design-gallery.md, blob-upload asset files, push gallery page (separate from wireframes-gallery).
---

# step-03 — gallery

Build a single Docs page hosting every hi-fi mockup, section per screen,
image rows per state. Optional — skipped if `documentation.platform = "none"`.

The gallery is **separate** from `wireframes-gallery`. They may coexist in
the same Docs space — design carries the hi-fi mockups, wireframes carry the
low-fi structural artifacts.

## Tasks

### A. Skip on documentation.platform=none

```bash
PLATFORM=$(jq -r '.documentation.platform // "none"' <<<"$CONFIG_JSON")
if [ "$PLATFORM" = "none" ]; then
  # Local render only.
  :
fi
```

If `$PLATFORM ∈ {affine, notion}`, push the page. Else render local
`design-gallery.md` and mark progress `skip` for publish.

### B. Render gallery markdown

Resolve staging path via `sync-push.sh`, render with `render-template.sh`:

```bash
STAGING=$(bash skills/_shared/sync-push.sh staging-path \
  --project-root="$PWD" \
  --story-id="$story_id" \
  --kind=design-gallery)

ctx=$(jq -n \
  --arg fid "$story_id" \
  --arg ftitle "$feature_title" \
  --argjson screens "$(jq '.screens' .snap/designs/${story_id}.draft.json)" \
  '{story_id:$fid, feature_title:$ftitle, screens:$screens}')

bash skills/_shared/render-template.sh \
  --template=skills/_shared/templates/docs-defaults/design-gallery.md \
  --vars="$ctx" \
  > "$STAGING"
```

### C. Upload assets as blobs

For each cached asset, upload via `docs-adapter.sh`:

```bash
bash skills/_shared/docs-adapter.sh \
  --action=upload-blob \
  --project-root="$PWD" \
  --file-path="$asset_path"
# exit 10 (MCP descriptor) → call MCP tool → capture blob_url
```

Replace each local `asset_path` in the rendered markdown with the remote
`blob_url` before pushing.

### D. Push gallery page

Parent page = the feature PRD page recorded in
`.snap/manifests/${story_id}.manifest.json` at `.refs.prd.page_id`:

```bash
PRD_PAGE_ID=$(jq -r '.refs.prd.page_id // ""' \
  ".snap/manifests/${story_id}.manifest.json")

create_out=$(bash skills/_shared/docs-adapter.sh \
  --action=create \
  --project-root="$PWD" \
  --parent-id="$PRD_PAGE_ID" \
  --title="Design — $feature_title" \
  --content-file="$STAGING")
GALLERY_PAGE_ID=$(jq -r '.page_id' <<<"$create_out")
GALLERY_URL=$(jq -r '.url' <<<"$create_out")
```

### E. Ack into manifest.refs.design_gallery

```bash
bash skills/_shared/sync-push.sh ack \
  --project-root="$PWD" \
  --story-id="$story_id" \
  --kind=design-gallery \
  --platform="$PLATFORM" \
  --url="$GALLERY_URL" \
  --page-id="$GALLERY_PAGE_ID"
```

### F. Telemetry + progress

```bash
bash skills/_shared/telemetry.sh log \
  --project-root="$PWD" --skill=design \
  --step-num=03 --step-name=gallery --status=ok \
  --extra='{"screens_count":'"$count"'}'

bash skills/_shared/progress.sh step \
  --project-root="$PWD" \
  --skill=design \
  --story-id="$story_id" \
  --step-num=03 \
  --step-name=gallery \
  --status=ok
```

## Failure handling

- Blob too large for AFFiNE / Notion → auto-downscale via `sips` (macOS) or
  `ffmpeg`. Second failure → mark progress `fail`.
- Page already exists (idempotent re-run): if
  `manifest.refs.design_gallery.page_id` already set, call `--action=update`
  against that page_id.

## Acceptance check

- Staging `design-gallery.md` rendered with one section per screen and a row
  per state.
- If platform ≠ "none": `manifest.refs.design_gallery.sync_status = "synced"`
  with `url` + `page_id` populated; staging trashed.

## Next step

→ `step-04-link.md`
