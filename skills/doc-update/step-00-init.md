---
step: 00-init
next_step: 01-collect
description: Parse args, require /snap:init, validate feature state, load PRD + journey refs from meta.json + domains.json.
---

# step-00 — init

Validate prerequisites. Fail loud, fail early.

## Tasks

1. **Require `/snap:init`** — exit early if missing:
   ```bash
   if [ ! -f "$PWD/snapship.config.json" ]; then
     echo "ERROR: snapship.config.json not found. Run /snap:init first." >&2
     exit 1
   fi
   ```

2. **Parse args** from `/snap:doc-update`:
   - `--feature=NN-slug` (required; partial-match on `feature_id`)
   - `--mode=diff|rewrite` (optional; overrides `documentation.auto_update_mode`)
   - `--dry-run` (default false)
   - `-a` / `--auto` (default false)

   Reject unknown `--mode` values.

3. **Resolve feature**:
   ```bash
   matches=$(ls -d .claude/product/features/${FEATURE}* 2>/dev/null)
   N=$(echo "$matches" | grep -c .)
   if [ "$N" -eq 0 ]; then
     echo "ERROR: no feature matches '${FEATURE}'." >&2; exit 1
   elif [ "$N" -gt 1 ]; then
     echo "ERROR: ambiguous feature '${FEATURE}' — matches:" >&2
     echo "$matches" >&2; exit 1
   fi
   FEATURE_DIR="$matches"
   FEATURE_ID=$(basename "$FEATURE_DIR")
   META="$FEATURE_DIR/meta.json"
   ```

4. **Validate feature state**:
   ```bash
   STATE=$(jq -r '.state' "$META")
   if [ "$STATE" != "qa-validated" ]; then
     echo "ERROR: feature ${FEATURE_ID} state=${STATE}, expected qa-validated." >&2
     echo "Run /snap:qa first." >&2; exit 1
   fi

   PRD_PAGE_ID=$(jq -r '.prd.page_id // ""' "$META")
   if [ -z "$PRD_PAGE_ID" ]; then
     echo "ERROR: feature ${FEATURE_ID} has no prd.page_id — was /snap:define publish step run?" >&2
     exit 1
   fi
   ```

5. **Load resolved config**:
   ```bash
   bash skills/_shared/load-config.sh --project-root="$PWD" >/dev/null
   PLATFORM=$(jq -r '.documentation.platform // "none"' .claude/product/.config-resolved.json)
   AUTO_UPDATE_MODE=$(jq -r '.documentation.auto_update_mode // "diff"' .claude/product/.config-resolved.json)
   WORKSPACE_ID=$(jq -r '.documentation.workspace.id // ""' .claude/product/.config-resolved.json)

   # CLI override
   [ -n "$MODE_OVERRIDE" ] && AUTO_UPDATE_MODE="$MODE_OVERRIDE"
   ```

   Fail loud if:
   - `PLATFORM == "none"` → log notice, mark progress `skip`, exit 0.
   - `PLATFORM ∉ {affine, notion}` → "ERROR: unsupported platform — re-run /snap:init"
   - `AUTO_UPDATE_MODE ∉ {diff, rewrite}` → reject

6. **MCP availability**:
   ```bash
   bash skills/_shared/check-mcp-required.sh \
     --required="$PLATFORM" \
     --available="$SNAP_MCP_AVAILABLE"
   ```
   Exit 1 if MCP not loaded.

7. **Resolve impacted journey page IDs from `domains.json`**:
   ```bash
   IMPACTED=$(jq -c '.impacted_journeys // []' "$META")
   if [ "$(echo "$IMPACTED" | jq 'length')" -eq 0 ]; then
     echo "ERROR: feature ${FEATURE_ID} has no impacted_journeys — nothing to update." >&2
     exit 1
   fi

   # Build resolved journey list: [{domain, journey_slug, page_id, url}, ...]
   JOURNEYS_RESOLVED="[]"
   for entry in $(echo "$IMPACTED" | jq -c '.[]'); do
     domain=$(echo "$entry" | jq -r '.domain')
     jslug=$(echo "$entry" | jq -r '.journey_slug')
     j=$(bash skills/_shared/domains-state.sh get-journey "$domain" "$jslug" --project-root="$PWD")
     if [ -z "$j" ] || [ "$j" = "null" ]; then
       echo "ERROR: journey ${domain}/${jslug} missing from domains.json — re-run /snap:define publish?" >&2
       exit 1
     fi
     page_id=$(echo "$j" | jq -r '.page_id')
     url=$(echo "$j" | jq -r '.url')
     JOURNEYS_RESOLVED=$(echo "$JOURNEYS_RESOLVED" | jq --arg d "$domain" --arg s "$jslug" \
       --arg pid "$page_id" --arg url "$url" \
       '. += [{domain:$d, journey_slug:$s, page_id:$pid, url:$url}]')
   done
   ```

8. **Hand off** to step-01 with vars:
   - `$FEATURE_ID`, `$FEATURE_DIR`, `$META`
   - `$PRD_PAGE_ID`
   - `$JOURNEYS_RESOLVED` (JSON array)
   - `$PLATFORM`, `$WORKSPACE_ID`, `$AUTO_UPDATE_MODE`
   - `$DRY_RUN`, `$AUTO`

## Acceptance check

- Feature resolved + state == `qa-validated`.
- All impacted journeys present in `domains.json` with `page_id`.
- MCP for `$PLATFORM` reachable.

## Next step

→ `step-01-collect.md`
