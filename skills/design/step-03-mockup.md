---
step: 03-mockup
next_step: 04-gallery
description: Per screen×state — frame hi-fi, apply DS components, export asset (penpot direct, figma via Bridge transport).
---

# step-03 — mockup

Generate hi-fi mockups. One page (or frame) per `(screen_id, state)`. Exactly
one export per page in the format declared by `design.export_format`.

Helper selection (resolved at step-00, in `$helper`):

| Platform | Helper                                  | Mockup compile path                                     |
|----------|-----------------------------------------|---------------------------------------------------------|
| `penpot` | `skills/_shared/penpot-helper.sh`       | Reuses wireframe surface; skill applies hi-fi shapes    |
| `figma`  | `skills/_shared/figma-bridge-helper.sh` | `bridge-ds mockup-compile` → transport `official|console` |

## Resolve export format (once)

```bash
fmt="$export_format" # from skill state (resolved at step-00)
canvas=$(jq -r '.design.mode_defaults.mockup_canvas // "desktop"' /tmp/cfg.json)
```

## Per-screen loop

For each screen in `.design-draft.json`, for each state in `states[]`:

### 1. Create page/frame

```bash
page_title="${feature_slug}-${screen_id}-${state}"

if [ "$ds_platform" = "penpot" ]; then
  bash "$helper" create-page \
    --title="$page_title" \
    --file-id="$ds_file_id" \
    --project-root="$PWD"
  # → exit 10 with descriptor → MCP creates page, returns page_id
else
  # figma: pages aren't created standalone; mockup-compile emits a frame
  # within the active file. Page id == frame node id after compile.
  :
fi
```

### 2. Compose mockup spec

Build a YAML CSpec (Bridge-compatible) or a shapes JSON per platform.

**figma** — emit a YAML CSpec referencing DS components:
```yaml
# .design-cache/${screen_id}-${state}.yaml
frame:
  name: "${page_title}"
  canvas: "${canvas}"
  background: "$page_bg"
children:
  - component: "Header"
    variant: "default"
    bind: { title: "${feature_title}" }
  - component: "FormCard"
    variant: "${state}"
    bind:
      fields:
        - { label: "Email", type: "email" }
        - { label: "Password", type: "password" }
  - component: "PrimaryButton"
    variant: "${state == "disabled" ? "disabled" : "enabled"}"
    bind: { label: "Sign up" }
```

**penpot** — emit a shapes JSON consumed by `add-shapes`:
```json
{
  "frame": {"name": "${page_title}", "width": 1440, "height": 900},
  "components": [
    {"ref":"Header", "x":0, "y":0, "bindings":{"title":"$feature_title"}},
    {"ref":"FormCard", "x":420, "y":200, "variant":"$state"}
  ]
}
```

Component refs resolve against the DS file (`design-system-page = Components`
for penpot; Bridge KB for figma).

### 3. Compile + push

#### 3.a — penpot

```bash
bash "$helper" add-shapes \
  --file-id="$ds_file_id" \
  --page-id="$page_id" \
  --shapes-file=".design-cache/${screen_id}-${state}.json" \
  --project-root="$PWD"
```

The shapes file references components by name; `penpot-helper.sh add-shapes`
resolves them via the `design.penpot.design_system_page` lookup.

#### 3.b — figma

```bash
bash "$helper" --action=mockup-compile \
  --kb-path="$ds_kb_path" \
  --scene-graph-file=".design-cache/${screen_id}-${state}.yaml" \
  --transport="$ds_transport" \
  --token-env="$ds_token_env"

if [ "$ds_transport" = "official" ]; then
  : # MCP executes the compiled JS — frame_id returned in dispatcher result
else
  echo "→ Paste $(jq -r .output_js .design-cache/${screen_id}-${state}.descriptor.json) into Figma DevTools."
  AskUserQuestion "Done pasting?"
fi
```

### 4. Export asset

```bash
target=".claude/product/features/${feature_id}/design/${page_title}.${fmt}"
mkdir -p "$(dirname "$target")"

if [ "$ds_platform" = "penpot" ]; then
  bash "$helper" export-png \
    --page-id="$page_id" \
    --output-path="$PWD/$target" \
    --format="$fmt" \
    --file-id="$ds_file_id"
else
  # figma: bridge-helper export-shape emits figma_execute exportAsync descriptor.
  exec_result=$(bash "$helper" --action=export-shape \
    --node-id="$frame_id" \
    --output-path="$target" \
    --format="$fmt" \
    --scale=2)
  # → dispatcher invokes figma_execute, captures result.data (base64).
  bash skills/_shared/figma-helper.sh save-export \
    --output-path="$target" \
    --base64-data="$exec_data"
fi
```

### 5. Cache descriptor

Append to `.design-draft.json`:

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

If the reuse decision at step-02 set a screen as "reused" (existing wireframe
asset reapplied without re-mocking), set `mode: "reused"` and leave
`asset_path` pointing to the wireframe png.

## Parallelism

Same constraint as `/wireframe`: serial within a feature. Penpot's plugin
context is single-tab; Figma Desktop runs a single active file. Issue calls
one at a time.

## Dry-run

`--dry-run` makes both helpers return mock descriptors (`DRY-{n}`),
`written:false`. No MCP calls. No assets written. Bridge `mockup-compile`
runs in dry-run via the bridge-helper's `--dry-run` flag and emits a
placeholder descriptor.

## Failure handling

Generic:
- MCP timeout / 5xx → retry once with 5s backoff. Second failure → mark
  progress `fail`. Cached pages from earlier screens persist.

Platform-specific:
- **penpot** — `add-shapes` rejecting a component ref means the
  `design.penpot.design_system_page` doesn't actually contain the named
  component. Halt with the component name + page name in the error.
- **figma** — Bridge `mockup-compile` failure usually means a `component:`
  reference doesn't exist in the KB. Run `bridge-ds extract` (the helper
  exposes `extract-ds`) to refresh KB from the live DS file, then resume.

## Append progress

```bash
bash skills/_shared/update-progress.sh \
  --project-root="$PWD" \
  --feature-id="$feature_id" \
  --step-num=03 \
  --step-name=mockup \
  --status=ok \
  --skill=design
```

## Acceptance check

- Every `(screen_id, state)` pair has an `asset_path` that exists on disk.
- `platform_page_id` is set (or `DRY-…` in dry-run).
- `mode` set to `mockup` (new) or `reused` (linked to existing wireframe).

## Next step

→ `step-04-gallery.md`
