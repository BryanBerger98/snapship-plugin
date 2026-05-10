---
step: 04-restructure
next_step: 05-finish
description: Execute the chosen strategy (synthesize / copy / move). Create snap hierarchy on AFFiNE/Notion; tag/move/synthesize source pages. Idempotent via [snap-imported] tag.
---

# step-04 — restructure

Apply the proposal. All write-side work happens here.

## Tasks

1. **Load proposal**:
   ```bash
   PROPOSAL=$(cat .claude/product/.doc-import-proposal.json)
   ```

2. **Ensure functional root exists** (idempotent):
   ```bash
   bash skills/_shared/docs-adapter.sh \
     --action=lookup-or-create-page \
     --platform="$PLATFORM" \
     --title="$FUNCTIONAL_ROOT" \
     --workspace-id="$WORKSPACE_ID" \
     ${DRY_RUN:+--dry-run}
   # Capture returned page_id as $FUNCTIONAL_ROOT_ID
   ```

3. **For each domain in proposal**:
   ```bash
   for d in $(echo "$PROPOSAL" | jq -r '.proposed_structure | keys[]'); do
     DOMAIN_TITLE=$(echo "$PROPOSAL" | jq -r ".proposed_structure[\"$d\"].title")

     # 3a. Create / lookup domain page under functional root
     bash skills/_shared/docs-adapter.sh \
       --action=lookup-or-create-page \
       --platform="$PLATFORM" \
       --title="$DOMAIN_TITLE" \
       --parent-id="$FUNCTIONAL_ROOT_ID" \
       ${DRY_RUN:+--dry-run}
     # → $DOMAIN_PAGE_ID

     # 3b. Cache to domains.json
     bash skills/_shared/domains-state.sh add-domain \
       "$d" "$DOMAIN_TITLE" "$DOMAIN_PAGE_ID" "$DOMAIN_PAGE_URL"
   done
   ```

4. **For each journey under each domain** — apply strategy:

   ### Strategy: synthesize
   ```
   For each (domain, journey) in proposal:
     - Read all source pages listed in source_pages[]
     - AI generate journey doc body from those sources (markdown body, ~500-2000
       words, structure: Overview / Steps / Edge cases / References)
     - Create journey page under domain page (lookup-or-create by title)
     - Write body via update-page-content
     - Tag each source page [snap-imported] (set-page-tags --tags='["snap-imported"]')
     - Cache journey page_id to domains.json (add-journey)
   ```

   ### Strategy: copy
   ```
   For each (domain, journey) in proposal:
     - For each source page in source_pages[]:
       - Read body
       - Create new page under domain (title = source title)
       - Write body verbatim via update-page-content
     - If multiple source pages, create a journey-index page that links to them;
       title = journey.title
     - Move source pages to "Archive/imported-{YYYY-MM-DD}" via parent_id update
       (single archive folder per import run, created lazily)
     - Cache journey page_id (use the index page when multi-source, else the
       single new page) to domains.json
   ```

   ### Strategy: move
   ```
   For each (domain, journey) in proposal:
     - If single source page → rename it to journey.title, reparent under domain
     - If multiple source pages → fail loud with message asking user to switch
       to synthesize/copy (move = 1:1, can't 1:N rename without losing pages)
     - Cache journey page_id to domains.json
   ```

5. **Per-page failure handling**:
   On MCP error for any single page, log to stderr with `page_id` + error +
   continue with next page. Track failures in `.doc-import-failures.ndjson`.
   At end, if failures > 0, print summary and exit 1 (step-05 will not run).

   Already-tagged `[snap-imported]` pages encountered mid-strategy are skipped
   (idempotent re-run).

6. **Dry run**:
   When `$DRY_RUN == true`, all docs-adapter calls receive `--dry-run`. No
   AFFiNE writes occur, but the strategy logic still runs (logs intended
   actions). `domains.json` is **not** written in dry-run mode.

7. **Telemetry per-domain**:
   ```bash
   bash skills/_shared/telemetry.sh append \
     --skill=doc-import \
     --status=ok \
     --extra="{\"domain\":\"$d\",\"journeys\":$JCOUNT,\"strategy\":\"$STRATEGY\"}"
   ```

## Acceptance check

- All domains in proposal have a page on the platform (or dry-run logged).
- All journeys created (or skipped via `[snap-imported]` tag).
- `.doc-import-failures.ndjson` empty OR was acted on by user.
- `domains.json` updated for non-dry runs.

## Next step

→ `step-05-finish.md`
