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
PLATFORM=$(jq -r '.documentation.platform // "none"' .claude/product/.config-resolved.json)
if [ "$PLATFORM" = "none" ]; then
  # Local render only.
  :
fi
```

If `$PLATFORM ∈ {affine, notion}`, push the page. Else render local
`design-gallery.md` and mark progress `skip` for publish.

### B. Render gallery markdown

```bash
ctx=$(jq -n \
  --arg fid "$feature_id" \
  --arg ftitle "$feature_title" \
  --argjson screens "$(jq '.screens' .claude/product/features/${feature_id}/.design-draft.json)" \
  '{feature_id:$fid, feature_title:$ftitle, screens:$screens}')

bash skills/_shared/render-template.sh \
  --template=skills/_shared/templates/docs-defaults/design-gallery.md \
  --vars="$ctx" \
  > .claude/product/design-gallery.md
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

```bash
bash skills/_shared/docs-adapter.sh \
  --action=create \
  --project-root="$PWD" \
  --parent-id="$(jq -r .prd_global.page_id .claude/product/.docs-cache.json)" \
  --title="Design — $feature_title" \
  --content-file=.claude/product/design-gallery.md
```

Cache result under `design_gallery.${feature_id}` in `.docs-cache.json`:

```json
{
  "design_gallery": {
    "01-signup": {"page_id": "...", "url": "https://..."}
  }
}
```

### E. Telemetry + progress

```bash
bash skills/_shared/telemetry.sh emit \
  --project-root="$PWD" --skill=design --status=ok \
  --extra='{"screens_count":'"$count"'}'

bash skills/_shared/update-progress.sh \
  --project-root="$PWD" --feature-id="$feature_id" \
  --step-num=03 --step-name=gallery --status=ok --skill=design
```

## Failure handling

- Blob too large for AFFiNE / Notion → auto-downscale via `sips` (macOS) or
  `ffmpeg`. Second failure → mark progress `fail`.
- Page already exists (idempotent re-run): update via `--action=update`,
  detected via `.docs-cache.json` lookup.

## Acceptance check

- Local `design-gallery.md` exists with one section per screen and a row
  per state.
- If platform ≠ "none": gallery URL cached.

## Next step

→ `step-04-link.md`
