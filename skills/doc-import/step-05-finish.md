---
step: 05-finish
description: Validate _taxonomy.json, write telemetry + progress entry, clean ephemeral state. Terminal step.
---

# step-05 — finish

Close out the import run.

## Tasks

1. **Validate `_taxonomy.json`** (skip in dry-run):
   ```bash
   if [ "$DRY_RUN" != "true" ]; then
     bash skills/_shared/taxonomy-state.sh validate --project-root="$PWD" \
       || { echo "ERROR: _taxonomy.json failed validate" >&2; exit 1; }
   fi
   ```

2. **Telemetry summary event**:
   ```bash
   STATUS=ok
   [ "$DRY_RUN" = "true" ] && STATUS=dry-run

   DOMAINS_COUNT=$(bash skills/_shared/taxonomy-state.sh list-domains \
     --project-root="$PWD" | wc -l | tr -d ' ')
   JOURNEYS_COUNT=$(bash skills/_shared/taxonomy-state.sh list-journeys \
     --project-root="$PWD" | wc -l | tr -d ' ')

   bash skills/_shared/telemetry.sh log \
     --project-root="$PWD" --skill=doc-import \
     --step-num=05 --step-name=finish --status="$STATUS" \
     --extra="{\"strategy\":\"$STRATEGY\",\"domains\":$DOMAINS_COUNT,\"journeys\":$JOURNEYS_COUNT,\"dry_run\":$DRY_RUN}"
   ```

3. **Append progress entry**:
   ```bash
   bash skills/_shared/progress.sh step \
     --project-root="$PWD" \
     --skill=doc-import \
     --story-id="_global" \
     --step-num=05 \
     --step-name=finish \
     --status="$STATUS"

   bash skills/_shared/progress.sh finish \
     --project-root="$PWD" \
     --skill=doc-import \
     --story-id="_global" \
     --status="$STATUS"
   ```

4. **Clean ephemeral state** (keeps backup if `--backup`):
   ```bash
   trash .snap/.doc-import-index.ndjson 2>/dev/null
   trash .snap/.doc-import-cache 2>/dev/null
   trash .snap/.doc-import-proposal.json 2>/dev/null
   trash .snap/.doc-import-failures.ndjson 2>/dev/null
   ```
   `.snap/.backup/{timestamp}/` is **kept** — user decides when to
   delete it.

5. **Print suggested next steps** to the user:
   ```
   ✓ doc-import done.
     Strategy: synthesize
     Domains: 2 (auth, dashboard)
     Journeys: 3 (login-flow, signup-flow, overview)
     Dry-run: no

   Next:
     /snap:define --story=NN-…      # first feature post-import
                                     # PRD will link to existing journeys via _taxonomy.json
     /snap:doc-import --force        # re-run if you want a different cluster split
   ```

## Acceptance check

- `progress.json` updated (in_flight entry removed).
- Telemetry NDJSON appended.
- No leftover `.doc-import-*` files (except `.backup/`).
- For non-dry run: `_taxonomy.json` validates.

## Next step

Terminal. Skill exits 0.
