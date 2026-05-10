---
step: 00-init
next_step: 01-crawl
description: Parse args, require /snap:init, validate documentation platform + MCP availability, guard against non-empty domains.json.
---

# step-00 — init

Validate prerequisites and parse args. Fail loud, fail early.

## Tasks

1. **Require `/snap:init`** — exit early if `snapship.config.json` missing:
   ```bash
   if [ ! -f "$PWD/snapship.config.json" ]; then
     echo "ERROR: snapship.config.json not found. Run /snap:init first." >&2
     exit 1
   fi
   ```

2. **Parse args** from `/snap:doc-import`:
   - `--source-page=<id-or-url>` (optional; default = workspace root)
   - `--strategy=synthesize|copy|move` (default `synthesize`)
   - `--dry-run` (default false)
   - `--backup` (default false)
   - `-a` / `--auto` (default false)
   - `--force` (default false — required to overwrite non-empty `domains.json`)

   Validate `--strategy` value; reject unknown.

3. **Load resolved config**:
   ```bash
   bash skills/_shared/load-config.sh --project-root="$PWD" >/dev/null
   PLATFORM=$(jq -r '.documentation.platform // "none"' .claude/product/.config-resolved.json)
   FUNCTIONAL_ROOT=$(jq -r '.documentation.paths.functional_root // ""' .claude/product/.config-resolved.json)
   WORKSPACE_ID=$(jq -r '.documentation.workspace.id // ""' .claude/product/.config-resolved.json)
   ```

   Fail loud if:
   - `PLATFORM == "none"` → "ERROR: documentation.platform=none — nothing to import"
   - `FUNCTIONAL_ROOT == ""` → should never happen (load-config injects default), but guard anyway
   - `PLATFORM` not in `{affine, notion}` → unsupported

4. **MCP availability**:
   ```bash
   bash skills/_shared/check-mcp-required.sh \
     --required="$PLATFORM" \
     --available="$SNAP_MCP_AVAILABLE"
   ```
   Exit 1 if MCP not loaded — user must enable the MCP server before retrying.

5. **`domains.json` non-empty guard**:
   ```bash
   COUNT=$(bash skills/_shared/domains-state.sh list-domains --project-root="$PWD" | wc -l | tr -d ' ')
   if [ "$COUNT" -gt 0 ] && [ "$FORCE" != "true" ]; then
     echo "ERROR: domains.json non-empty (${COUNT} domain(s) already imported)." >&2
     echo "Re-run with --force to re-import (existing entries will be overwritten)." >&2
     exit 1
   fi
   ```

6. **`--backup` warning** (if not set):
   Print to stderr a non-blocking warning recommending `--backup` for `move`
   strategy specifically (history preserved on AFFiNE side, but local archive
   is cheap insurance).

7. **Hand off** to step-01 with shell vars:
   - `$SOURCE_PAGE` (page id/url or empty)
   - `$STRATEGY` (synthesize|copy|move)
   - `$DRY_RUN` (true|false)
   - `$BACKUP` (true|false)
   - `$AUTO` (true|false)
   - `$FORCE` (true|false)
   - `$PLATFORM` (affine|notion)
   - `$FUNCTIONAL_ROOT` (e.g. "Product Docs")
   - `$WORKSPACE_ID`

## Acceptance check

- All required env vars set.
- `domains.json` either empty or `--force` confirmed.
- MCP for `$PLATFORM` confirmed reachable.

## Next step

→ `step-01-crawl.md`
