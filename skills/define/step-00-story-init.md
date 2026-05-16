---
step: 00-story-init
next_step: 01-vision
description: Mode story — parse args, require snap.config.json, detect codebase, branch greenfield vs extension. Entry when define_mode=story (selected by step-00-detect-mode).
---

# step-00 — story init (mode story entry)

Validate that the workspace was bootstrapped (`/snap:init`) and decide which
path to follow. **Config bootstrap is not handled here** — if
`snap.config.json` is missing, this step exits early and points the user back
to `/snap:init`.

## Tasks

1. **Parse args** from the user's `/snap:define` invocation. Recognize `--resume`/`-r`,
   `--lang=fr|en`, `--story=NN-slug` (alias déprécié : `--feature=`),
   `--epic=PARENT_EPIC_ID`.

   `--epic=` captures the platform-native Epic ID (ex. `AUTH-1`, `#42`, `&12`).
   No validation here — `/snap:ticket` validates against the target platform.
   Empty string if flag absent.

2. **Resume short-circuit**: if `--resume` flag passed, delegate to `progress.sh resume`:
   ```bash
   resume_line=$(bash skills/_shared/progress.sh resume \
     --project-root="$PWD" \
     --skill=define \
     --story-id="${feature:-_global}")
   ```
   - Non-empty → parse `NUM\tNAME\tSTATUS`, jump to `step-${NUM}-${NAME}.md` with
     `story_id` pre-loaded. Skip the rest of this step.
   - Empty → no in-flight run; fall through to step-00 init normally.

   For partial `--story` matches, resolve against
   `.snap/manifests/*.manifest.json` filenames — "01" or "auth" → first match.
   Ambiguous → surface candidate list and re-prompt.

3. **Require config**: `snap.config.json` must exist at `$PWD`. If absent,
   abort early with:
   ```
   ERROR: snap.config.json not found at <PWD>.
   Run /snap:init first to bootstrap the workspace.
   ```
   Do not scaffold, do not write progress. Just exit.

4. **Project root + codebase detection**: run `detect-codebase.sh` and parse
   the verdict. The helper is the **single source of truth** for both « is
   `$PWD` a project root ? » and « is there an existing codebase ? » — its
   `signals[]` array enumerates every manifest / `.git` marker found.
   ```bash
   verdict=$(bash skills/_shared/detect-codebase.sh --project-root="$PWD")
   has_codebase=$(echo "$verdict" | jq -r '.has_codebase')
   signals=$(echo "$verdict" | jq -r '.signals | join(", ")')
   ```
   Show `signals` to the user when announcing the chosen path so they can
   override the heuristic if needed (e.g., "Detected codebase via:
   package.json, .git"). If `signals` is empty AND `has_codebase=false`, ask
   the user to confirm `$PWD` before proceeding — legit greenfield directory
   but no signal to anchor against.

5. **Update transient state file** (merge-update — the routeur step-00 already
   created the file with `define_mode`. We only patch the keys this step
   owns: `codebase_mode`, `lang`, optional `active_story_id`):
   ```bash
   bash skills/_shared/define-state.sh init \
     --project-root="$PWD" \
     --lang="$lang" \
     --codebase-mode="$codebase_mode" \
     ${story_id:+--story="$story_id"}
   ```

   `codebase_mode` ∈ `{greenfield, extension}` (issu de `detect-codebase.sh`,
   task 4 ci-dessus). Ne pas confondre avec `define_mode` ∈ `{vision, journey,
   story}` qui appartient au routeur.

   If `--epic=PARENT_EPIC_ID` was passed in Task 1, persist it now :
   ```bash
   if [ -n "${epic:-}" ]; then
     bash skills/_shared/define-state.sh set cli_parent_epic_id "$epic" \
       --project-root="$PWD"
   fi
   ```
   Consumed by `step-03-features.md` Task 7 to skip the Parent Epic question.

6. **Capture resolved config** into a shell variable **and** persist a
   snapshot in `.define-state.json` so step-04/05 survive a `--resume` after
   process exit (T3):
   ```bash
   CONFIG_JSON=$(bash skills/_shared/load-config.sh --project-root="$PWD")
   bash skills/_shared/define-state.sh set-config-snapshot "$CONFIG_JSON" \
     --project-root="$PWD"
   ```
   Fail loud on non-zero exit. `.snap/` already exists (scaffolded by
   `/snap:init`). Subsequent steps read fields via `jq -r '...' <<<"$CONFIG_JSON"`
   in the same process **or** hydrate from
   `define-state.sh get-config-snapshot` on resume (fallback to a fresh
   `load-config.sh` if the snapshot is empty / corrupt).

7. **Mode branch**:
   - `has_codebase = false` → **greenfield** path: full vision walkthrough
     (steps 01 → 02 → 03 → 04 → 05).
   - `has_codebase = true` AND `--story` not set → **extension** path: ask the
     user whether to create a new feature or extend an existing one. New = same
     flow. Extend = jump to `step-03-features.md` with existing taxonomy loaded
     as context.
   - `--story=NN-slug` set → jump straight to `step-03-features.md` and
     pre-fill `story_id`.

8. **Register skill run in progress.json**:
   ```bash
   bash skills/_shared/progress.sh step \
     --project-root="$PWD" \
     --skill=define \
     --story-id="${ACTIVE_FEATURE:-_global}" \
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
| `story_id` | `--story` or chosen later | step-03 onward |
| `codebase_mode` | `greenfield` \| `extension` | step-01..03 |
| `CONFIG_JSON` | `load-config.sh` stdout (mirrored to `.define-state.json.config_snapshot`) | step-04/05 (paths, platform) |

## Acceptance check

- `.snap/` exists and is writable.
- `CONFIG_JSON` parses as JSON.
- `.snap/progress.json` has an `in_flight` entry for `define` with a step
  `{num:"00", name:"init", status:"ok"}`.

If any check fails, write `status=fail` via `progress.sh step` and stop with a
clear error message. Do **not** move to `step-01-vision.md`.

## Next step

→ `step-01-vision.md` (greenfield) **or** branch override above.
