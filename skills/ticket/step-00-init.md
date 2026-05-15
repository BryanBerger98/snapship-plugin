---
step: 00-init
next_step: 01-load
description: Parse args, resolve feature_id, load resolved config, block if tickets.platform=none, branch on resume.
---

# step-00 — init

Bootstrap a `/snap:ticket` run for a single feature.

## Tasks

1. **Parse args**: `--resume`/`-r`, `--feature=PARTIAL`, `--platform=…`,
   `--max-stories=N`, `--dry-run`.

2. **Require config + load** :
   ```bash
   [ -f "$PWD/snapship.config.json" ] || {
     echo "ERROR: snapship.config.json not found. Run /snap:init first." >&2
     exit 1
   }
   CONFIG_JSON=$(bash skills/_shared/load-config.sh --project-root="$PWD")
   platform=$(jq -r '.tickets.platform' <<<"$CONFIG_JSON")
   ```
   `--platform=` arg overrides the resolved value.

3. **Block if no tracker** (v1.0 hard-block) :
   ```bash
   if [ "$platform" = "none" ]; then
     echo "ERROR: tickets.platform is \"none\" — no tracker configured." >&2
     echo "Re-run /snap:init --force to set a tracker, then retry /snap:ticket." >&2
     exit 1
   fi
   ```
   Do **not** write progress entry; this is a config error, not a run failure.

4. **Resume short-circuit** : if `--resume`, delegate to `progress.sh resume` :
   ```bash
   resume_line=$(bash skills/_shared/progress.sh resume \
     --project-root="$PWD" \
     --skill=ticket \
     --feature-id="${feature_id:-_global}")
   ```
   - Non-empty → parse `NUM\tNAME\tSTATUS`, jump to `step-${NUM}-${NAME}.md` with
     `feature_id` pre-loaded. Skip the rest of this step.
   - Empty → fall through to step-00 fresh.

5. **Resolve `feature_id`** : if not passed and not resumed :
   - Single manifest in `.snap/manifests/*.manifest.json` (excluding
     `_taxonomy.json`) → use it.
   - Multiple → `AskUserQuestion` with the list of `feature_id` options.
   - Zero → abort with "Run `/snap:define` first".

   For partial matches (`--feature=auth`), list manifest filenames and apply :
   exact → numeric prefix (`01`) → slug substring (`auth`). Bail on ambiguity
   with the candidate list.

6. **Pre-flight checks** :
   - Manifest exists : `.snap/manifests/${feature_id}.manifest.json`.
   - Manifest has `refs.prd.sync_status = "synced"` (PRD already published —
     prerequisite for ticketing). If not synced, abort with pointer to
     `/snap:define --resume --feature=$feature_id`.
   - Tickets-adapter MCP / CLI requirements met :
     ```bash
     bash skills/_shared/check-mcp-required.sh --skill=ticket --project-root="$PWD"
     ```

7. **Register skill run + first step** :
   ```bash
   bash skills/_shared/progress.sh step \
     --project-root="$PWD" \
     --skill=ticket \
     --feature-id="$feature_id" \
     --step-num=00 \
     --step-name=init \
     --status=ok
   ```

## Variables to record (in-context)

| Var | Source | Used by |
|-----|--------|---------|
| `feature_id`   | arg / detection | step-01..06 |
| `platform`     | config / arg | step-04 (template), step-05 (adapter) |
| `max_stories`  | arg (default 12) | step-02 |
| `dry_run`      | arg / env | step-05 |
| `CONFIG_JSON`  | `load-config.sh` stdout | step-04 (templates config), step-05 |

## Acceptance check

- `feature_id` resolved.
- Manifest exists with `refs.prd.sync_status = "synced"`.
- `tickets.platform != "none"`.
- `progress.json.in_flight` has a `ticket` entry with step `00 init ok`.

## Next step

→ `step-01-load.md`
