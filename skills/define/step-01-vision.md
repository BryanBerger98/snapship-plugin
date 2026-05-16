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

1. **Source of truth = `_taxonomy.workspace`**. The taxonomy is the long-term
   store (edited by `--mode=vision`). The define-state is a transient mirror
   used by step-04 to render. Bootstrap + read first :

   ```bash
   bash skills/_shared/taxonomy-state.sh init --project-root="$PWD"
   WS=$(bash skills/_shared/taxonomy-state.sh get-workspace --project-root="$PWD")
   WS_VISION=$(echo "$WS" | jq -r '.vision // ""')
   WS_METRIC=$(echo "$WS" | jq -r '.north_star.metric  // ""')
   WS_CURRENT=$(echo "$WS" | jq -r '.north_star.current // ""')
   WS_TARGET=$(echo "$WS" | jq -r '.north_star.target  // ""')
   WS_HORIZON=$(echo "$WS" | jq -r '.north_star.horizon // ""')
   ```

   **Skip condition** : if `WS_VISION` and `WS_METRIC` are both non-empty,
   skip all `AskUserQuestion` prompts. Mirror the taxonomy values into
   `.define-state.json` (so step-04 finds them at a single read site) and
   log the skip :

   ```bash
   bash skills/_shared/define-state.sh set vision             "$WS_VISION"  --project-root="$PWD"
   bash skills/_shared/define-state.sh set north_star_metric  "$WS_METRIC"  --project-root="$PWD"
   bash skills/_shared/define-state.sh set north_star_current "$WS_CURRENT" --project-root="$PWD"
   bash skills/_shared/define-state.sh set north_star_target  "$WS_TARGET"  --project-root="$PWD"
   bash skills/_shared/define-state.sh set target_horizon     "$WS_HORIZON" --project-root="$PWD"
   bash skills/_shared/progress.sh step \
     --project-root="$PWD" --skill=define --story-id=_global \
     --step-num=01 --step-name=vision --status=skip \
     --note="reused from _taxonomy.workspace"
   ```
   Then jump to step-02.

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

4. **Ask current + target + horizon** in a **single** `AskUserQuestion` call
   (3 questions, max 4 per call — batch to cut round-trips) :
   - "Current value of `{north_star_metric}` (or 'unknown' if not measured yet)"
   - "Target value at horizon"
   - "Target horizon (e.g. Q3 2026, 6 months, end of year)"

   Save as `north_star_current`, `north_star_target`, `target_horizon`.

5. **Validate**: vision must be at least 50 chars (anti-junk action-verb check
   handled by LLM gate at step 2, not by helper regex). North star metric
   must be a non-empty string. If validation fails, re-ask with the validation
   reason shown to the user.

6. **Dual-write : taxonomy first, define-state mirror**. Persist the new vision
   + north star in the long-term taxonomy, then mirror into the transient
   define-state for step-04 :

   ```bash
   bash skills/_shared/taxonomy-state.sh set-vision "$vision" --project-root="$PWD"
   bash skills/_shared/taxonomy-state.sh set-north-star \
     "$nsm" "$nsc" "$nst" "$horizon" --project-root="$PWD"

   bash skills/_shared/define-state.sh set vision             "$vision"  --project-root="$PWD"
   bash skills/_shared/define-state.sh set north_star_metric  "$nsm"     --project-root="$PWD"
   bash skills/_shared/define-state.sh set north_star_current "$nsc"     --project-root="$PWD"
   bash skills/_shared/define-state.sh set north_star_target  "$nst"     --project-root="$PWD"
   bash skills/_shared/define-state.sh set target_horizon     "$horizon" --project-root="$PWD"
   ```

   Taxonomy survives `define-state.sh wipe` (step-05); the next `/snap:define`
   run will trigger the skip-condition in Task 1.

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
