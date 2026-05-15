---
step: 01-write
next_step: null
description: Materialize snapship.config.json, scaffold .snap/ via setup-snap-dir.sh, validate via load-config.sh. Terminal step.
terminal: true
---

# step-01 — write

Terminal step. Persist config + scaffold local workspace.

## Tasks

1. **Write config** via `setup-config.sh --write` :
   ```bash
   # SNAP_MCP_AVAILABLE doit être forwardé pour que la détection auto retrouve
   # les mêmes defaults qu'au step-00 (sans ça, --auto-mode peut faillir).
   ARGS=( --write --project-root="$PWD" )
   [ "$auto" = "true" ]    && ARGS+=( --auto-mode=true )
   [ "$force" = "true" ]   && ARGS+=( --force )
   [ -n "$lang_override" ] && ARGS+=( --lang="$lang_override" )
   [ -n "$answers_json" ]  && ARGS+=( --from-answers="$answers_json" )
   [ -n "${SNAP_MCP_AVAILABLE:-}" ] && ARGS+=( --available="$SNAP_MCP_AVAILABLE" )

   bash skills/_shared/setup-config.sh "${ARGS[@]}"
   ```
   Exit codes :
   - `0` → config written at `$PWD/snapship.config.json`.
   - `1` → bad args / autonomous mode missing required field. Surface stderr to
     the user and stop. Do **not** scaffold `.snap/`.
   - `2` → existing config + no `--force`. Should never reach here (step-00
     guards it), but fail clean with the same message.

2. **Scaffold `.snap/`** (idempotent — no feature_id at init time) :
   ```bash
   bash skills/_shared/setup-snap-dir.sh --project-root="$PWD"
   ```
   This creates :
   - `.snap/manifests/_taxonomy.json` (with `schema_version`, empty `workspace`,
     `domains`, `journeys`)
   - `.snap/progress.json` (with `schema_version`, empty `in_flight`)
   - `.snap/{PRDs,designs,wireframes,tickets,queues}/` empty dirs
   - `.snap/.doc-import/cache/` empty dir

3. **Validate resolved config** :
   ```bash
   bash skills/_shared/load-config.sh --project-root="$PWD" >/dev/null
   ```
   Stdout (resolved JSON) is discarded here — we only care about exit 0 (schema
   passes). Fail loud on non-zero (schema violation, invalid JSON).

4. **Validate taxonomy bootstrap** :
   ```bash
   bash skills/_shared/taxonomy-state.sh validate --project-root="$PWD"
   ```

5. **Progress entry** :
   ```bash
   bash skills/_shared/progress.sh step \
     --project-root="$PWD" \
     --skill=init \
     --feature-id=_global \
     --step-num=01 \
     --step-name=write \
     --status=ok
   bash skills/_shared/progress.sh finish \
     --project-root="$PWD" \
     --skill=init \
     --feature-id=_global \
     --status=ok
   ```

6. **Telemetry** :
   ```bash
   bash skills/_shared/telemetry.sh log \
     --project-root="$PWD" \
     --skill=init \
     --step-num=01 \
     --step-name=write \
     --status=ok
   ```

## Acceptance check

- `snapship.config.json` exists at project root and parses as JSON.
- `load-config.sh` exits 0.
- `.snap/manifests/_taxonomy.json` exists and validates.
- `.snap/progress.json` exists with `in_flight: []`.
- `.snap/{PRDs,designs,wireframes,tickets,queues,.doc-import/cache}/` all present.
- If `documentation.platform != "none"`, resolved config has both
  `documentation.paths.functional_root` and `documentation.paths.prd_root` set
  (defaults `"Product Docs"` / `"Change Requests"` apply automatically).

## Next step

Terminal. Suggest to the user :

```
✓ snap workspace ready.

Next :
  /snap:define          # start your first feature PRD
  /snap:define -a       # autonomous mode (no prompts)
```
