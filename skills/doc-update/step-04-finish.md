---
step: 04-finish
description: Telemetry summary, progress entry, clean ephemeral cache. Terminal step.
---

# step-04 — finish

Close out the run.

## Tasks

1. **Append progress entry**:
   ```bash
   STATUS=ok
   [ "$DRY_RUN" = "true" ] && STATUS=dry-run

   bash skills/_shared/update-progress.sh \
     --project-root="$PWD" \
     --feature-id="$FEATURE_ID" \
     --step-num=04 \
     --step-name=finish \
     --status="$STATUS" \
     --skill=doc-update
   ```

2. **Telemetry summary**:
   ```bash
   N_JOURNEYS=$(echo "$JOURNEYS_RESOLVED" | jq 'length')

   bash skills/_shared/telemetry.sh append \
     --project-root="$PWD" \
     --skill=doc-update \
     --status="$STATUS" \
     --extra="{\"feature\":\"$FEATURE_ID\",\"journeys\":$N_JOURNEYS,\"mode\":\"$AUTO_UPDATE_MODE\",\"dry_run\":$DRY_RUN}"
   ```

3. **Clean ephemeral cache** (keep on dry-run for inspection):
   ```bash
   if [ "$DRY_RUN" != "true" ]; then
     trash ".claude/product/.doc-update-cache/${FEATURE_ID}" 2>/dev/null
   fi
   ```

4. **Print summary**:
   ```
   ✓ doc-update done.
     Feature: 01-auth (Sign-up with email)
     Mode: diff
     Journeys updated: 2 (auth/login-flow, auth/signup-flow)
     PRD page: untouched (immutable archive)
     Dry-run: no
   ```

## Acceptance check

- `progress.md` has `doc-update step-04 finish — {ok|dry-run|skip}`.
- Telemetry NDJSON appended.
- Cache wiped (unless dry-run).

## Next step

_None — terminal step._
