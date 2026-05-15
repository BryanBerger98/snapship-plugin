---
step: 04-finish
description: Telemetry summary, progress entry, clean ephemeral cache. Terminal step.
---

# step-04 — finish

Close out the run.

## Tasks

1. **Telemetry summary**:
   ```bash
   STATUS=ok
   [ "$DRY_RUN" = "true" ] && STATUS=dry-run

   N_JOURNEYS=$(echo "$JOURNEYS_RESOLVED" | jq 'length')

   bash skills/_shared/telemetry.sh log \
     --project-root="$PWD" --skill=doc-update \
     --step-num=04 --step-name=finish --status="$STATUS" \
     --extra="{\"feature\":\"$FEATURE_ID\",\"journeys\":$N_JOURNEYS,\"mode\":\"$AUTO_UPDATE_MODE\",\"dry_run\":$DRY_RUN}"
   ```

2. **Append progress entry + close run**:
   ```bash
   bash skills/_shared/progress.sh step \
     --project-root="$PWD" \
     --skill=doc-update \
     --feature-id="$FEATURE_ID" \
     --step-num=04 \
     --step-name=finish \
     --status="$STATUS"

   bash skills/_shared/progress.sh finish \
     --project-root="$PWD" \
     --skill=doc-update \
     --feature-id="$FEATURE_ID" \
     --status="$STATUS"
   ```

3. **Clean ephemeral cache** (keep on dry-run for inspection):
   ```bash
   if [ "$DRY_RUN" != "true" ]; then
     trash ".snap/.doc-update-cache/${FEATURE_ID}" 2>/dev/null
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

- `progress.json` in_flight entry removed.
- Telemetry NDJSON appended.
- Cache wiped (unless dry-run).

## Next step

_None — terminal step._
