---
step: 01-vision
next_step: 02-personas
description: Capture product vision, north star metric, and target horizon via AskUserQuestion.
---

# step-01 — vision

Collect the product's vision and its single tracked metric.

## Inputs

- `mode` from step-00 (`greenfield` | `extension`).
- Optional: existing `prd-global.md` (extension mode) — read it first for context.

## Tasks

1. **Skip condition**: if `mode = extension` AND existing `prd-global.md` already has a
   non-empty Vision section AND a North Star Metric, skip to step-02 with the existing
   values cached. Note the skip in `progress.md`.

2. **Ask vision** via `AskUserQuestion` (single open prompt — let the user free-write,
   do not constrain to options):

   > "In one paragraph: who is your product for, what change does it make in their life,
   > and why now?"

   Save as `vision`.

3. **Ask north star metric** via `AskUserQuestion` with 4 options (multiSelect: false):
   - Activation rate
   - Weekly active users (WAU)
   - Revenue / ARR
   - Custom

   If `Custom`, follow up with a free-text question for the metric name. Save as
   `north_star_metric`.

4. **Ask current and target values** via `AskUserQuestion` (free text):
   - "Current value of `{north_star_metric}` (or 'unknown' if not measured yet)"
   - "Target value at horizon"
   - "Target horizon (e.g. Q3 2026, 6 months, end of year)"

   Save as `north_star_current`, `north_star_target`, `target_horizon`.

5. **Validate**: vision must be at least 50 chars and contain a verb. North star metric
   must be a non-empty string. If validation fails, re-ask with the validation reason
   shown to the user.

6. **Cache** the collected values in `.claude/product/.define-state.json` (working state,
   discarded after step-04 succeeds):
   ```json
   {
     "step": "01-vision",
     "vision": "...",
     "north_star_metric": "...",
     "north_star_current": "...",
     "north_star_target": "...",
     "target_horizon": "..."
   }
   ```

7. **Append progress**:
   ```bash
   bash skills/_shared/update-progress.sh \
     --project-root="$PWD" \
     --feature-id=_global \
     --step-num=01 \
     --step-name=vision \
     --status=ok \
     --skill=define
   ```

## Acceptance check

- `.define-state.json` contains `vision`, `north_star_metric`, `north_star_current`,
  `north_star_target`, `target_horizon` — all non-empty.
- Vision passes the 50-char + verb sanity check.

## Next step

→ `step-02-personas.md`
