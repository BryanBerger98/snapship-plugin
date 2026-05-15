---
step: 00-init
next_step: 01-vision
description: Parse args, require snapship.config.json, detect codebase, branch greenfield vs extension.
---

# step-00 — init

Validate that the workspace was bootstrapped (`/snap:init`) and decide which
path to follow. **Config bootstrap is not handled here** — if
`snapship.config.json` is missing, this step exits early and points the user back
to `/snap:init`.

## Tasks

1. **Parse args** from the user's `/snap:define` invocation. Recognize `--resume`/`-r`,
   `--lang=fr|en`, `--feature=NN-slug`.

2. **Resume short-circuit**: if `--resume` flag passed, delegate to `progress.sh resume`:
   ```bash
   resume_line=$(bash skills/_shared/progress.sh resume \
     --project-root="$PWD" \
     --skill=define \
     --feature-id="${feature:-_global}")
   ```
   - Non-empty → parse `NUM\tNAME\tSTATUS`, jump to `step-${NUM}-${NAME}.md` with
     `feature_id` pre-loaded. Skip the rest of this step.
   - Empty → no in-flight run; fall through to step-00 init normally.

   For partial `--feature` matches, resolve against
   `.snap/manifests/*.manifest.json` filenames — "01" or "auth" → first match.
   Ambiguous → surface candidate list and re-prompt.

3. **Require config**: `snapship.config.json` must exist at `$PWD`. If absent,
   abort early with:
   ```
   ERROR: snapship.config.json not found at <PWD>.
   Run /snap:init first to bootstrap the workspace.
   ```
   Do not scaffold, do not write progress. Just exit.

4. **Project root detection**: confirm `$PWD` is the project root (presence of
   `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, `composer.json`, or
   `.git`). If not found, ask the user to confirm the path before proceeding.

5. **Codebase detection**: run `detect-codebase.sh` and parse the verdict :
   ```bash
   verdict=$(bash skills/_shared/detect-codebase.sh --project-root="$PWD")
   has_codebase=$(echo "$verdict" | jq -r '.has_codebase')
   signals=$(echo "$verdict" | jq -r '.signals | join(", ")')
   ```
   Show `signals` to the user when announcing the chosen path so they can override
   the heuristic if needed (e.g., "Detected codebase via: package.json, .git").

6. **Initialize transient state file** (consumed by step-01..04, wiped by step-05):
   ```bash
   bash skills/_shared/define-state.sh init \
     --project-root="$PWD" \
     --lang="$lang" \
     --mode="$mode" \
     ${feature_id:+--feature="$feature_id"}
   ```

7. **Capture resolved config** into a shell variable (load-config writes nothing
   to disk in v1.0 — stdout only):
   ```bash
   CONFIG_JSON=$(bash skills/_shared/load-config.sh --project-root="$PWD")
   ```
   Fail loud on non-zero exit. `.snap/` already exists (scaffolded by
   `/snap:init`). Subsequent steps read fields via `jq -r '...' <<<"$CONFIG_JSON"`.

8. **Mode branch**:
   - `has_codebase = false` → **greenfield** path: full vision walkthrough
     (steps 01 → 02 → 03 → 04 → 05).
   - `has_codebase = true` AND `--feature` not set → **extension** path: ask the
     user whether to create a new feature or extend an existing one. New = same
     flow. Extend = jump to `step-03-features.md` with existing taxonomy loaded
     as context.
   - `--feature=NN-slug` set → jump straight to `step-03-features.md` and
     pre-fill `feature_id`.

9. **Register skill run in progress.json**:
   ```bash
   bash skills/_shared/progress.sh step \
     --project-root="$PWD" \
     --skill=define \
     --feature-id="${ACTIVE_FEATURE:-_global}" \
     --step-num=00 \
     --step-name=init \
     --status=ok
   ```
   (auto-starts the skill-run entry — no separate `start` call needed)

## Variables to record (in-context for later steps)

| Var | Source | Used by |
|-----|--------|---------|
| `has_codebase` | detection | step-01 (skip vision if extending) |
| `lang` | `--lang` or detected | step-04 (template rendering) |
| `feature_id` | `--feature` or chosen later | step-03 onward |
| `mode` | `greenfield` \| `extension` | step-01..03 |
| `CONFIG_JSON` | `load-config.sh` stdout | step-05 (paths, platform) |

## Acceptance check

- `.snap/` exists and is writable.
- `CONFIG_JSON` parses as JSON.
- `.snap/progress.json` has an `in_flight` entry for `define` with a step
  `{num:"00", name:"init", status:"ok"}`.

If any check fails, write `status=fail` via `progress.sh step` and stop with a
clear error message. Do **not** move to `step-01-vision.md`.

## Next step

→ `step-01-vision.md` (greenfield) **or** branch override above.
