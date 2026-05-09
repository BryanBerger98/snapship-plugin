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
2. **Resume short-circuit**: if `--resume` and `.claude/product/progress.md` exists,
   delegate to the resume protocol (see `step-00-resume.md`). Do not continue this
   step — `step-00-resume.md` will compute the next step and jump there.
3. **Project root detection**: confirm `$PWD` is the project root (presence of
   `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, `composer.json`, or `.git`).
   If not found, ask the user to confirm the path before proceeding.
4. **Codebase detection**: set `has_codebase = true` if any of the manifest files above
   exist OR `git rev-parse --is-inside-work-tree` succeeds AND there is at least one
   tracked source file. Otherwise `has_codebase = false` (greenfield).
5. **Scaffold** `.claude/product/` if missing:
   ```
   .claude/product/
     prd-global.md          # rendered later in step-04
     features/              # one dir per feature
     progress.md            # append-only run log
     telemetry.ndjson       # append via skills/_shared/telemetry.sh
     .config-resolved.json  # produced by load-config.sh on first run
   ```
6. **Run** `bash skills/_shared/load-config.sh --project-root="$PWD"` to materialize the
   resolved config. If the project lacks `artysan.config.json`, run
   `skills/_shared/setup-config.sh` first (interactive).
7. **Mode branch**:
   - `has_codebase = false` → **greenfield** path: full vision walkthrough (steps
     01 → 04 → 05).
   - `has_codebase = true` AND `--feature` not set → **extension** path: ask the user
     whether to create a new feature or extend an existing one. New = same flow.
     Extend = jump to `step-03-features.md` with the existing `prd-global.md` loaded
     as context.
   - `--feature=NN-slug` set → jump straight to `step-03-features.md` and pre-fill
     `feature_id`.
8. **Append progress entry**:
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
