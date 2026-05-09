---
step: 01-write
description: Materialize artysan.config.json, scaffold .claude/product/, validate via load-config.sh.
---

# step-01 — write

Terminal step. Persist config + scaffold local cache.

## Tasks

1. **Write config** via `setup-config.sh --write`:
   ```bash
   ARGS=( --write --project-root="$PWD" )
   [ "$auto" = "true" ]    && ARGS+=( --auto-mode=true )
   [ "$force" = "true" ]   && ARGS+=( --force )
   [ -n "$lang_override" ] && ARGS+=( --lang="$lang_override" )
   [ -n "$answers_json" ]  && ARGS+=( --from-answers="$answers_json" )

   bash skills/_shared/setup-config.sh "${ARGS[@]}"
   ```
   Exit codes:
   - `0` → config written at `$PWD/artysan.config.json`.
   - `1` → bad args / autonomous mode missing required field. Surface stderr to
     the user and stop. Do **not** scaffold `.claude/product/`.
   - `2` → existing config + no `--force`. Should never reach here (step-00
     guards it), but fail clean with the same message.

2. **Scaffold `.claude/product/`** (idempotent):
   ```bash
   mkdir -p "$PWD/.claude/product/features"
   touch    "$PWD/.claude/product/progress.md"
   touch    "$PWD/.claude/product/telemetry.ndjson"
   ```
   If `progress.md` is empty, write a header:
   ```
   # Artysan progress log

   Append-only run log. Entries written by `_shared/update-progress.sh`.
   ```

3. **Materialize resolved config**:
   ```bash
   bash skills/_shared/load-config.sh --project-root="$PWD" >/dev/null
   ```
   Side effect: writes `.claude/product/.config-resolved.json`. Fail loud on
   non-zero exit (schema violation, invalid JSON).

4. **Append progress entry**:
   ```bash
   bash skills/_shared/update-progress.sh \
     --project-root="$PWD" \
     --feature-id="_global" \
     --step-num=01 \
     --step-name=write \
     --status=ok \
     --skill=init
   ```

5. **Telemetry**:
   ```bash
   bash skills/_shared/telemetry.sh append \
     --project-root="$PWD" \
     --skill=init \
     --status=ok
   ```

## Acceptance check

- `artysan.config.json` exists at project root and parses as JSON.
- `load-config.sh` exits 0.
- `.claude/product/{features,progress.md,telemetry.ndjson,.config-resolved.json}`
  all present.

## Next step

Terminal. Suggest to the user:

```
✓ artysan workspace ready.

Next:
  /artysan:define          # start your first feature PRD
  /artysan:define -a       # autonomous mode (no prompts)
```
