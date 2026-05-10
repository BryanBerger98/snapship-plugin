---
step: 01-crawl
next_step: 02-analyze
description: List source pages from AFFiNE/Notion subtree (or workspace root), build local index for analysis. Skip pages already tagged [snap-imported].
---

# step-01 — crawl

Build a flat index of candidate pages to analyze in step-02.

## Tasks

1. **Build crawl descriptor** via docs-adapter:
   ```bash
   bash skills/_shared/docs-adapter.sh \
     --action=search \
     --platform="$PLATFORM" \
     --query="*" \
     --limit=500 \
     ${SOURCE_PAGE:+--page-id="$SOURCE_PAGE"} \
     ${WORKSPACE_ID:+--workspace-id="$WORKSPACE_ID"}
   ```
   Exit 10 = MCP descriptor — model maps `{platform: affine, action: search}` to
   the actual MCP tool (e.g. `mcp__affine-mcp-server__search_pages`) and
   executes it.

   When `$SOURCE_PAGE` is set, scope = subtree of that page (recursive). When
   absent, scope = entire workspace.

2. **Build page index** as NDJSON (one page per line) — write to
   `.claude/product/.doc-import-index.ndjson`:
   ```json
   {"page_id":"abc","title":"Login screen","parent_id":"root","tags":[],"updated_at":"...","char_count":4231,"path":"Engineering/Auth/Login screen"}
   ```

   Fields:
   - `page_id`, `title`, `parent_id`, `tags[]`, `updated_at` — from MCP response
   - `char_count` — strlen of body content (used by step-02 to weigh signal)
   - `path` — full breadcrumb (parent chain joined by `/`)

3. **Filter out already-imported pages**:
   Drop any page whose `tags` contains `snap-imported`. These were processed by
   a prior partial run.

4. **Backup** (if `$BACKUP == true`):
   ```bash
   BACKUP_DIR=".claude/product/.backup/$(date -u +%Y%m%dT%H%M%SZ)"
   mkdir -p "$BACKUP_DIR"
   ```
   For each indexed page, fetch full content via `docs-adapter --action=get` and
   save body to `$BACKUP_DIR/{page_id}.md` with frontmatter (`title`, `path`,
   `updated_at`, `tags`).

5. **Empty-index guard**:
   ```bash
   COUNT=$(wc -l < .claude/product/.doc-import-index.ndjson | tr -d ' ')
   if [ "$COUNT" -eq 0 ]; then
     echo "ERROR: source scope contains 0 pages — nothing to import." >&2
     echo "Check --source-page or AFFiNE workspace permissions." >&2
     exit 1
   fi
   ```

## Acceptance check

- `.claude/product/.doc-import-index.ndjson` exists, non-empty.
- Each line is valid JSON with required keys.
- If `--backup`, every page in index has a corresponding `.md` in `$BACKUP_DIR`.

## Next step

→ `step-02-analyze.md`
