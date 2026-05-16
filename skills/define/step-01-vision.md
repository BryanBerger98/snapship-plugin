---
step: 01-vision
next_step: 02-personas
description: Capture product vision, north star metric, and target horizon via AskUserQuestion.
---

# step-01 — vision

Collect the product's vision and its single tracked metric.

## Inputs

- `codebase_mode` from step-00-story-init (`greenfield` | `extension`).
- Optional: existing `.snap/manifests/*.manifest.json` + workspace metadata in
  `_taxonomy.json` (extension mode) — read first for context.

## Tasks

1. **Skip condition**: if `codebase_mode = extension` AND the workspace already has cached
   vision + north star metric in `.snap/.define-state.json` (or in the taxonomy
   workspace metadata), skip to step-02 with the existing values reused. Note
   the skip via `progress.sh step --status=skip`.

2. **Ask vision** via `AskUserQuestion` (single open prompt — let the user free-write,
   do not constrain to options):

   > "In one paragraph: who is your product for, what change does it make in their life,
   > and why now?"

   Save as `vision`.

   **Anti-junk gate (LLM-judged, multilingue natif)** : avant de persister,
   juger la réponse. Si la phrase ne décrit pas une **action / transformation**
   (= que des adjectifs marketing, ou taxonomie marché sans verbe d'action en
   `$lang`), re-prompt avec la raison :

   > "La vision saisie décrit un état / une catégorie, pas un changement.
   > Reformule avec un verbe d'action — qui, quel changement, pourquoi."

   Exemples à rejeter :
   - « Une plateforme moderne et performante pour freelances » → adjectifs.
   - « SaaS B2B vertical pour PME industrielles » → taxonomie, pas d'action.

   Exemples à accepter :
   - « Aide les freelances à facturer leurs clients en 30 secondes ».
   - « Permet aux PME industrielles de réduire leur empreinte carbone ».

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

5. **Validate**: vision must be at least 50 chars (anti-junk action-verb check
   handled by LLM gate at step 2, not by helper regex). North star metric
   must be a non-empty string. If validation fails, re-ask with the validation
   reason shown to the user.

6. **Cache** the collected values via `define-state.sh`:
   ```bash
   bash skills/_shared/define-state.sh set vision "$vision" --project-root="$PWD"
   bash skills/_shared/define-state.sh set north_star_metric "$nsm" --project-root="$PWD"
   bash skills/_shared/define-state.sh set north_star_current "$nsc" --project-root="$PWD"
   bash skills/_shared/define-state.sh set north_star_target "$nst" --project-root="$PWD"
   bash skills/_shared/define-state.sh set target_horizon "$horizon" --project-root="$PWD"
   ```
   The state file `.snap/.define-state.json` was created by `define-state.sh init`
   in step-00.

7. **Append progress**:
   ```bash
   bash skills/_shared/progress.sh step \
     --project-root="$PWD" \
     --skill=define \
     --story-id=_global \
     --step-num=01 \
     --step-name=vision \
     --status=ok
   ```

## Acceptance check

- `.define-state.json` contains `vision`, `north_star_metric`, `north_star_current`,
  `north_star_target`, `target_horizon` — all non-empty.
- Vision passes the 50-char + verb sanity check.

## Next step

→ `step-02-personas.md`
