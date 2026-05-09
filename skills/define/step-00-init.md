---
step: 00-init
next_step: 01-vision
description: Parse args, detect codebase, scaffold .claude/product/, branch greenfield vs extension.
---

# step-00 — init

Bootstrap the artysan workspace and decide which path to follow.

## Tasks

1. **Parse args** from the user's `/define` invocation. Recognize `--resume`/`-r`,
   `--lang=fr|en`, `--feature=NN-slug`.
2. **Resume short-circuit**: if `--resume` flag passed, delegate to `resume-state.sh`:
   ```bash
   resume_json=$(bash skills/_shared/resume-state.sh next \
     --skill=define \
     --project-root="$PWD" \
     ${feature:+--feature="$feature"})
   rc=$?
   ```
   - `rc=0` → parse `next_step` and `feature_id` from JSON, jump to that step file
     (e.g. `step-04-render.md`) with `feature_id` pre-loaded. Skip the rest of this step.
   - `rc=1` → no in-flight run; surface the `reason` and fall through to step-00 init
     normally (treat as fresh start).
   - `rc=2` → bad args; abort with the stderr message.

   For partial `--feature` matches, `resume-state.sh` resolves "01" or "auth" to the
   full `feature_id` and returns it in the JSON; ambiguous matches exit non-zero with
   a candidate list — surface that to the user and re-prompt.
3. **Project root detection**: confirm `$PWD` is the project root (presence of
   `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, `composer.json`, or `.git`).
   If not found, ask the user to confirm the path before proceeding.
4. **Codebase detection**: run `bash skills/_shared/detect-codebase.sh --project-root="$PWD"`
   and parse the JSON verdict:
   ```bash
   verdict=$(bash skills/_shared/detect-codebase.sh --project-root="$PWD")
   has_codebase=$(echo "$verdict" | jq -r '.has_codebase')
   signals=$(echo "$verdict" | jq -r '.signals | join(", ")')
   ```
   Show `signals` to the user when announcing the chosen path so they can override
   the heuristic if needed (e.g., "Detected codebase via: package.json, .git").
5. **Initialize state file**:
   ```bash
   bash skills/_shared/define-state.sh init \
     --project-root="$PWD" \
     --lang="$lang" \
     --mode="$mode" \
     ${feature_id:+--feature="$feature_id"}
   ```

6. **Scaffold** `.claude/product/` if missing:
   ```
   .claude/product/
     prd-global.md          # rendered later in step-04
     features/              # one dir per feature
     progress.md            # append-only run log
     telemetry.ndjson       # append via skills/_shared/telemetry.sh
     .config-resolved.json  # produced by load-config.sh on first run
   ```
7. **Bootstrap config** — explicit existence check, do **not** rely on
   `load-config.sh` to fail (it treats missing config as empty `{}`):
   ```bash
   CONFIG_FILE="$PWD/artysan.config.json"
   if [ ! -f "$CONFIG_FILE" ]; then
     # 7a. detect defaults from .git/config + available MCPs + structure
     detected=$(bash skills/_shared/setup-config.sh --detect \
       --project-root="$PWD" \
       ${ARTYSAN_MCP_AVAILABLE:+--available="$ARTYSAN_MCP_AVAILABLE"})
     # 7b. drive AskUserQuestion to confirm/override fields (repository.platform,
     #     tickets.platform, documentation.platform, wireframes.platform, lang).
     #     In `-a` autonomous mode, skip prompts and use detected defaults via
     #     `--auto-mode=true` instead.
     # 7c. write config from merged answers
     bash skills/_shared/setup-config.sh --write \
       --project-root="$PWD" \
       --from-answers="$answers_json"
   fi
   bash skills/_shared/load-config.sh --project-root="$PWD"
   ```
   Materializes `.claude/product/.config-resolved.json` for downstream steps.
8. **Mode branch**:
   - `has_codebase = false` → **greenfield** path: full vision walkthrough (steps
     01 → 04 → 05).
   - `has_codebase = true` AND `--feature` not set → **extension** path: ask the user
     whether to create a new feature or extend an existing one. New = same flow.
     Extend = jump to `step-03-features.md` with the existing `prd-global.md` loaded
     as context.
   - `--feature=NN-slug` set → jump straight to `step-03-features.md` and pre-fill
     `feature_id`.
9. **Append progress entry**:
   ```bash
   bash skills/_shared/update-progress.sh \
     --project-root="$PWD" \
     --feature-id="${ACTIVE_FEATURE:-_global}" \
     --step-num=00 \
     --step-name=init \
     --status=ok \
     --skill=define
   ```

## Variables to record (in-context for later steps)

| Var | Source | Used by |
|-----|--------|---------|
| `has_codebase` | detection | step-01 (skip vision if extending) |
| `lang` | `--lang` or detected | step-04 (template rendering) |
| `feature_id` | `--feature` or chosen later | step-03 onward |
| `mode` | `greenfield` \| `extension` | step-01..03 |

## Acceptance check

- `.claude/product/` exists and is writable.
- Resolved config loaded without error.
- `progress.md` has an entry `define step-00 init — ok`.

If any check fails, write `status=fail` to progress and stop with a clear error message.
Do **not** move to `step-01-vision.md`.

## Next step

→ `step-01-vision.md` (greenfield) **or** branch override above.
