---
step: 05-publish
description: Push rendered PRDs to AFFiNE/Notion via docs-adapter, cache page IDs in meta.json. Terminal step.
---

# step-05 — publish

Final step. Pushes the local PRDs to the configured docs platform and caches the
returned page IDs/URLs in each feature's `meta.json` and `.docs-cache.json`.

This step has no `next_step` — it is terminal.

## Inputs

- `.claude/product/prd-global.md` (from step-04)
- `.claude/product/features/{feature_id}/prd-feature.md` per feature
- `artysan.config.json` → `documentation.platform` ∈ {`affine`, `notion`, `none`}

## Tasks

### A. Skip if platform = none

If `documentation.platform = "none"`, log a notice and skip publish. Mark progress
`skip` with note `documentation.platform=none`. Stop.

### B. Push global PRD

```bash
bash skills/_shared/docs-adapter.sh \
  --action=create \
  --project-root="$PWD" \
  --title="PRD — $(jq -r .product_name artysan.config.json)" \
  --content-file=.claude/product/prd-global.md
```

Both AFFiNE and Notion are MCP-only — the adapter exits 10 with an MCP descriptor on
stdout. The model:

1. Parses the descriptor (`{"descriptor":{"tool":"mcp__affine__create_page","args":{...}}}`).
2. Invokes the named MCP tool with the given args.
3. Captures `page_id` and `url` from the MCP response.
4. Writes them to `.claude/product/.docs-cache.json` under `prd_global`:
   ```json
   { "prd_global": { "page_id": "...", "url": "..." } }
   ```

### C. Push per-feature PRDs

For each `feature_id` in `.claude/product/features/`:

```bash
bash skills/_shared/docs-adapter.sh \
  --action=create \
  --project-root="$PWD" \
  --parent-id="$(jq -r .prd_global.page_id .claude/product/.docs-cache.json)" \
  --title="$(jq -r .feature_name .claude/product/features/${fid}/meta.json)" \
  --content-file=".claude/product/features/${fid}/prd-feature.md"
```

After the MCP call returns, update the feature's `meta.json`:
```bash
jq --arg pid "$page_id" --arg url "$url" \
  '.affine_page_id = $pid | .affine_url = $url | .updated_at = now | strftime("%Y-%m-%dT%H:%M:%SZ")' \
  ".claude/product/features/${fid}/meta.json" \
  > "${fid}-meta.tmp" && mv "${fid}-meta.tmp" ".claude/product/features/${fid}/meta.json"
```

(Use `notion_page_id` / `notion_url` keys when `platform = notion`.)

Re-validate `meta.json` against `meta.schema.json` after every mutation:
```bash
ajv validate -s skills/_shared/schemas/meta.schema.json \
  -d ".claude/product/features/${fid}/meta.json" --spec=draft2020 --strict=false
```

### D. Telemetry

```bash
bash skills/_shared/telemetry.sh emit \
  --project-root="$PWD" \
  --skill=define \
  --status=ok \
  --duration-ms="$elapsed_ms" \
  --extra='{"features_count": '"$count"', "platform": "'"$platform"'"}'
```

### E. Progress

```bash
bash skills/_shared/update-progress.sh \
  --project-root="$PWD" \
  --feature-id=_global \
  --step-num=05 \
  --step-name=publish \
  --status=ok \
  --skill=define
```

### F. Cleanup

```bash
bash skills/_shared/define-state.sh wipe --project-root="$PWD"
```

Keep `.claude/product/.docs-cache.json` (read by `/ticket`, `/wireframe`).

## Failure handling

- **MCP error** (auth, rate limit, page already exists with conflict): retry once with
  exponential backoff. If the second attempt fails, write `progress.md` `status=fail`
  with the MCP error verbatim and stop. The local PRDs remain — `/define --resume` will
  retry from step-05.
- **Schema validation failure on meta.json after mutation**: revert the mutation, log
  the error, mark progress `fail`. Stop.
- **Mid-loop failure** (some features pushed, others not): the per-feature meta.json
  already contains `affine_page_id` for those that succeeded, so a re-run skips them
  (check `meta.affine_page_id != null` before pushing).

## Acceptance check

- Each feature has `affine_page_id` (or `notion_page_id`) recorded in its `meta.json`,
  OR `documentation.platform = "none"`.
- `progress.md` ends with `define step-05 publish — ok` (or `skip`).
- Telemetry event emitted with `status=ok|skip`.

## Next step

_None — terminal step._
