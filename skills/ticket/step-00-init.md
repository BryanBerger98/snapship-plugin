---
step: 00-init
next_step: 01-load
description: Parse args, resolve story_id, load resolved config, block if tickets.platform=none, branch on resume.
---

# step-00 — init

Bootstrap a `/snap:ticket` run for a single feature.

## Communication language (`defaults.lang`)

Once `CONFIG_JSON` is loaded below, resolve the configured language and respond
to the user in it for the whole skill run (prompts, questions, summaries):

```bash
SNAP_LANG=$(jq -r '.defaults.lang // "fr"' <<<"$CONFIG_JSON")
```

**Directive**: communicate with the user in `$SNAP_LANG` (`fr` = français,
`en` = English, …). Presentation directive only — never translate config keys,
file paths, or code identifiers.

## Progress persistence (`defaults.save_mode`)

Resolve `save_mode` once (default `true`) right after `CONFIG_JSON` is loaded:

```bash
save_mode=$(jq -r '.defaults.save_mode // true' <<<"$CONFIG_JSON")
```

**Directive**: pass `--save-mode="$save_mode"` to **every** `progress.sh`
`start`/`step`/`finish` invocation in this skill. When `save_mode=false` the
helper turns those writes into no-ops (no `.snap/progress.json`); reads
(`resume`/`list`) are unaffected.

## Tasks

1. **Parse args**: `--resume`/`-r`, `--feature=PARTIAL`, `--platform=…`,
   `--max-stories=N`, `--dry-run`, `--standalone`, `--auto`,
   `--keep-runtime` (debug — skip purge at step-06).

   - `--standalone` (v1.2) — opt-in mode: skip PRD load (step-01 short-circuit),
     forbid `story_type=epic` in drafts (decision #5). Use when ticket flow is
     run outside of a `/snap:define` context (ad-hoc bug, isolated task, etc).
   - `--auto` (v1.2) — bulk mode: hierarchy clustering + metadata assignment
     decided by inline LLM with explicit warn ; user confirms en bloc post-format.
     Requires TTY for the final confirm, else falls back to fail-clean error.

2. **Require config + load** :
   ```bash
   [ -f "$PWD/snap.config.json" ] || {
     echo "ERROR: snap.config.json not found. Run /snap:init first." >&2
     exit 1
   }
   CONFIG_JSON=$(bash skills/_shared/load-config.sh --project-root="$PWD")
   platform=$(jq -r '.tickets.platform' <<<"$CONFIG_JSON")
   ```
   `--platform=` arg overrides the resolved value.

   **Resolve `auto_mode`** — config is the standing default, the `--auto`/`-a`
   CLI flag overrides it for this run:
   ```bash
   auto_mode=$(jq -r '.defaults.auto_mode // false' <<<"$CONFIG_JSON")
   [ "$auto_arg" = "true" ] && auto_mode=true   # --auto / -a forces it on
   ```
   Pass `--auto-mode="$auto_mode"` to every `ask-or-default.sh` invocation in
   later steps (step-03b clustering, step-03c metadata).

3. **Block if no tracker** (v1.0 hard-block) :
   ```bash
   if [ "$platform" = "none" ]; then
     echo "ERROR: tickets.platform is \"none\" — no tracker configured." >&2
     echo "Re-run /snap:init --force to set a tracker, then retry /snap:ticket." >&2
     exit 1
   fi
   ```
   Do **not** write progress entry; this is a config error, not a run failure.

3a. **GitHub native routing — lazy self-heal** (v1.1):

   If `platform = "github"` and `tickets.github` is absent from the resolved
   config, the install pre-dates the native-routing change. Offer a one-shot
   detect + map prompt; otherwise the run silently falls back to label-only
   behaviour (v1.0 compatible).

   ```bash
   if [ "$platform" = "github" ] && [ -z "$(jq -r '.tickets.github // empty' <<<"$CONFIG_JSON")" ]; then
     # AskUserQuestion (single-select):
     #  - "Configurer Issue Type + Project maintenant (recommandé)"
     #  - "Continuer avec labels seulement (skip définitivement, écrit tickets.github.enabled=false)"
     #
     # On "configure": run detect-github-fields.sh, AskUserQuestion to map
     # type/priority/size/scope, write the resulting tickets.github.* block into
     # snap.config.json (atomic write via tmp + mv), reload CONFIG_JSON.
     #
     # On "skip": write `{"tickets":{"github":{"enabled":false}}}` so the
     # prompt never reappears. apply-github-metadata.sh respects this flag and
     # returns story labels verbatim (residual = labels).
     :
   fi
   ```

   The self-heal runs once per project. Users who reconsider can re-run
   `/snap:upgrade` (re-detects + re-prompts) or delete `tickets.github` from
   the config to retrigger the prompt on the next `/snap:ticket`.

4. **Resume short-circuit** : if `--resume`, delegate to `progress.sh resume` :
   ```bash
   resume_line=$(bash skills/_shared/progress.sh resume \
     --project-root="$PWD" \
     --skill=ticket \
     --story-id="${story_id:-_global}")
   ```
   - Non-empty → parse `NUM\tNAME\tSTATUS`, jump to `step-${NUM}-${NAME}.md` with
     `story_id` pre-loaded. Skip the rest of this step.
   - Empty → fall through to step-00 fresh.

5. **Resolve `story_id`** (skipped if `--standalone`) : if not passed and not resumed :
   - Single manifest in `.snap/manifests/*.manifest.json` (excluding
     `_taxonomy.json`) → use it.
   - Multiple → `AskUserQuestion` with the list of `story_id` options.
   - Zero → abort with "Run `/snap:define` first".

   For partial matches (`--feature=auth`), list manifest filenames and apply :
   exact → numeric prefix (`01`) → slug substring (`auth`). Bail on ambiguity
   with the candidate list.

6. **Pre-flight checks** :
   - `--standalone` mode: skip manifest + PRD checks. `story_id` defaults to
     `_standalone` for progress.sh bookkeeping. Forbid `story_type=epic` on
     drafts produced downstream (decision #5 — Epic always implies a structured
     PRD parent).
   - Normal mode:
     - Manifest exists : `.snap/manifests/${story_id}.manifest.json`.
     - Manifest has `refs.prd.sync_status = "synced"` (PRD already published —
       prerequisite for ticketing). If not synced, abort with pointer to
       `/snap:define --resume --story=$story_id`.
   - Tickets-adapter MCP / CLI requirements met :
     ```bash
     bash skills/_shared/check-mcp-required.sh --skill=ticket --project-root="$PWD"
     ```

7. **Initialize ephemeral runtime cache** (v1.2 — decision #2) :

   Skill-scoped subject directory under `.snap/.runtime/<subject-id>/` holds
   draft tickets, tracker context, and bulk decision artefacts. Purged at
   step-06 (success or failure) unless `--keep-runtime` debug flag set.

   ```bash
   SUBJECT_ID=$(bash skills/_shared/cache-runtime.sh id-gen --prefix=ticket)
   bash skills/_shared/cache-runtime.sh init "$SUBJECT_ID" --project-root="$PWD"

   # Trap purge — every exit path (success, failure, signal) cleans up
   # the subject directory. --keep-runtime opts out (debug only).
   if [ "${KEEP_RUNTIME:-false}" != "true" ]; then
     trap 'bash skills/_shared/cache-runtime.sh purge "$SUBJECT_ID" --project-root="$PWD" >/dev/null 2>&1 || true' EXIT
   fi
   ```

   Record `SUBJECT_ID` in context — all subsequent steps reference it for
   read/write of ephemeral state. Persistent artefacts (`.snap/tickets/`,
   manifests, progress.json) are NOT in this cache.

8. **Register skill run + first step** :
   ```bash
   bash skills/_shared/progress.sh step \
     --project-root="$PWD" \
     --skill=ticket \
     --story-id="$story_id" \
     --step-num=00 \
     --step-name=init \
     --status=ok
   ```

## Variables to record (in-context)

| Var | Source | Used by |
|-----|--------|---------|
| `story_id`   | arg / detection | step-01..06 |
| `platform`     | config / arg | step-04 (template), step-05 (adapter) |
| `max_stories`  | arg (default 12) | step-02 |
| `dry_run`      | arg / env | step-05 |
| `standalone`   | `--standalone` arg | step-01 (skip PRD), step-04 (refuse epic), step-05 |
| `auto_mode`    | `defaults.auto_mode` (config) ∨ `--auto`/`-a` arg | step-03b, step-03c (clustering / metadata) — passed as `--auto-mode=` to `ask-or-default.sh` |
| `keep_runtime` | `--keep-runtime` arg | step-06 (skip purge) |
| `SUBJECT_ID`   | `cache-runtime.sh id-gen` | step-01..06 (ephemeral state) |
| `CONFIG_JSON`  | `load-config.sh` stdout | step-04 (templates config), step-05 |

## Acceptance check

- `story_id` resolved (skipped when `--standalone`).
- Manifest exists with `refs.prd.sync_status = "synced"` (skipped when `--standalone`).
- `tickets.platform != "none"`.
- `SUBJECT_ID` generated and `.snap/.runtime/<SUBJECT_ID>/` exists.
- EXIT trap registered for purge (unless `--keep-runtime`).
- `progress.json.in_flight` has a `ticket` entry with step `00 init ok`.

## Next step

→ `step-01-load.md`
