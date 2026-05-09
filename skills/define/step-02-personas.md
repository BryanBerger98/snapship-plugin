---
step: 02-personas
next_step: 03-features
description: Capture 1-N personas with role, goals, pain points, and tools.
---

# step-02 — personas

Build the persona list that anchors every feature decision.

## Tasks

1. **Skip condition**: extension mode + existing personas in `prd-global.md` → ask
   "Add another persona?" (yes/no). If no, skip to step-03 with cached personas.

2. **Loop** until the user is done (max 5 personas — push back if more):

   For each persona, ask via `AskUserQuestion`:

   - **Name / archetype** (free text, e.g. "Sarah, freelance designer")
   - **Role** (free text, 1 sentence)
   - **Top 3 goals** (free text, comma-separated)
   - **Top 3 pain points** (free text, comma-separated)
   - **Tools they use today** (free text, comma-separated; informs integrations later)

3. **Continue?** After each persona, ask `AskUserQuestion` (multiSelect: false):
   - "Add another persona"
   - "Done — proceed to features"

   Stop on "Done" or after 5 personas (with a one-line note that more personas can
   be added by re-running `/define --resume` later).

4. **Validate**: at least 1 persona collected. Each persona has non-empty role + at
   least 1 goal + 1 pain point.

5. **Cache** in `.claude/product/.define-state.json`:
   ```json
   {
     "step": "02-personas",
     "personas": [
       {
         "persona_name": "...",
         "persona_role": "...",
         "persona_goals": "...",
         "persona_pains": "...",
         "persona_tools": "..."
       }
     ]
   }
   ```

6. **Append progress**:
   ```bash
   bash skills/_shared/update-progress.sh \
     --project-root="$PWD" \
     --feature-id=_global \
     --step-num=02 \
     --step-name=personas \
     --status=ok \
     --skill=define
   ```

## Acceptance check

- `personas` array has at least 1 entry.
- Each entry has `persona_role`, `persona_goals`, `persona_pains` non-empty.

## Next step

→ `step-03-features.md`
