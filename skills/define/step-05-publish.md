---
step: 05-publish
description: Push rendered PRDs to AFFiNE/Notion via docs-adapter, cache page IDs in meta.json. Terminal step.
---

# step-05 — publish

Final step. Pushes the local PRDs to the configured docs platform and caches the
returned page IDs/URLs in each feature's `meta.json`.

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
bash skills/_shared/docs-adapter.sh push \
  --project-root="$PWD" \
  --kind=prd-global \
  --file=.claude/product/prd-global.md
```

The adapter returns either:
- **MCP descriptor** (exit code 10): a JSON object on stdout describing the MCP call
  the model must execute (e.g., `mcp__affine__create_or_update_page` with payload).
  The model executes the MCP tool, captures `page_id` and `url`, then re-runs the
  adapter with `--mcp-result=<json>` to record the result.
- **Direct success** (exit code 0): adapter handled the push (rare — only if a CLI
  is available; AFFiNE is MCP-only). JSON on stdout: `{ "page_id": "...", "url": "..." }`.

Cache the returned `page_id` and `url` in `.claude/product/.docs-cache.json` (top-level
`prd_global` key).

### C. Push per-feature PRDs

For each feature in `.claude/product/features/`:

```bash
bash skills/_shared/docs-adapter.sh push \
  --project-root="$PWD" \
  --kind=prd-feature \
  --feature-id="$fid" \
  --file=".claude/product/features/${fid}/prd-feature.md" \
  --parent-page-id="$(jq -r .prd_global.page_id .claude/product/.docs-cache.json)"
```

Update `meta.json` with `affine_page_id` + `affine_url` (or `notion_page_id` +
`notion_url` based on platform). Re-validate `meta.json` against the schema after
mutation.

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

Delete `.claude/product/.define-state.json` (working state — no longer needed).
Keep `.claude/product/.docs-cache.json` (read by `/ticket`, `/wireframe`).

## Failure handling

- **MCP error** (auth, rate limit, page already exists with conflict): retry once with
  exponential backoff. If the second attempt fails, write `progress.md` `status=fail`
  with the MCP error verbatim and stop. The local PRDs remain — `/define --resume` will
  retry from step-05.
- **Schema validation failure on meta.json after mutation**: revert the mutation, log
  the error, mark progress `fail`. Stop.

## Acceptance check

- Each feature has `affine_page_id` (or `notion_page_id`) recorded in its `meta.json`,
  OR `documentation.platform = "none"`.
- `progress.md` ends with `define step-05 publish — ok` (or `skip`).
- Telemetry event emitted with `status=ok|skip`.

## Next step

_None — terminal step._
