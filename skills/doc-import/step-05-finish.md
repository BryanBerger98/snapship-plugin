---
step: 05-finish
description: Persist domains.json, write telemetry + progress entry, clean ephemeral state. Terminal step.
---

# step-05 — finish

Close out the import run.

## Tasks

1. **Validate `domains.json`** (skip in dry-run):
   ```bash
   if [ "$DRY_RUN" != "true" ]; then
     bash skills/_shared/domains-state.sh validate --project-root="$PWD" \
       || { echo "ERROR: domains.json failed validate" >&2; exit 1; }
   fi
   ```

2. **Append progress entry**:
   ```bash
   STATUS=ok
   [ "$DRY_RUN" = "true" ] && STATUS=dry-run

   bash skills/_shared/update-progress.sh \
     --project-root="$PWD" \
     --feature-id="_global" \
     --step-num=05 \
     --step-name=finish \
     --status="$STATUS" \
     --skill=doc-import
   ```

3. **Telemetry summary event**:
   ```bash
   DOMAINS_COUNT=$(bash skills/_shared/domains-state.sh list-domains | wc -l | tr -d ' ')
   JOURNEYS_COUNT=$(bash skills/_shared/domains-state.sh list-journeys | wc -l | tr -d ' ')

   bash skills/_shared/telemetry.sh append \
     --project-root="$PWD" \
     --skill=doc-import \
     --status="$STATUS" \
     --extra="{\"strategy\":\"$STRATEGY\",\"domains\":$DOMAINS_COUNT,\"journeys\":$JOURNEYS_COUNT,\"dry_run\":$DRY_RUN}"
   ```

4. **Clean ephemeral state** (keeps backup if `--backup`):
   ```bash
   trash .claude/product/.doc-import-index.ndjson 2>/dev/null
   trash .claude/product/.doc-import-cache 2>/dev/null
   trash .claude/product/.doc-import-proposal.json 2>/dev/null
   trash .claude/product/.doc-import-failures.ndjson 2>/dev/null
   ```
   `.claude/product/.backup/{timestamp}/` is **kept** — user decides when to
   delete it.

5. **Print suggested next steps** to the user:
   ```
   ✓ doc-import done.
     Strategy: synthesize
     Domains: 2 (auth, dashboard)
     Journeys: 3 (login-flow, signup-flow, overview)
     Dry-run: no

   Next:
     /snap:define --feature=NN-…    # first feature post-import
                                     # PRD will link to existing journeys via domains.json
     /snap:doc-import --force        # re-run if you want a different cluster split
   ```

## Acceptance check

- `progress.md` has new entry.
- Telemetry NDJSON appended.
- No leftover `.doc-import-*` files (except `.backup/`).
- For non-dry run: `domains.json` validates.

## Next step

Terminal. Skill exits 0.
