---
step: 03-apply
next_step: 04-validate
description: Applique chaque migration script de la chaîne dans l'ordre. Si fail, rollback depuis backup.
---

# step-03 — apply migrations

Exécute la chaîne migrations résolue par step-00.

## Tâches

1. **Lit le plan** : `.snap/.upgrade-plan.json` + `.snap/.upgrade-decisions.json`.

2. **Pour chaque migration** dans `chain[]` (déjà ordonnée par version) :
   - **Mode dry-run** : ajoute `SNAP_DRY_RUN=true`.
   - Lance le script :
     ```bash
     SNAP_PROJECT_ROOT="$(pwd)" \
     SNAP_DECISIONS_JSON="$(cat .snap/.upgrade-decisions.json)" \
     SNAP_DRY_RUN="${DRY_RUN:-false}" \
       bash "skills/_shared/migrations/${MIG_SCRIPT}"
     ```
   - Capture stdout/stderr ; log par migration.
   - Si exit ≠ 0 :
     - Log fail (telemetry).
     - **Rollback** : si backup existe et `dry-run=false` →
       ```bash
       trash .snap || true
       trash .claude/product || true
       mv "$BACKUP_DIR" .snap   # ou .claude/product selon source
       ```
     - Abort skill avec message explicite.

3. **Telemetry par migration** :
   ```bash
   bash skills/_shared/telemetry.sh log --skill=upgrade --step-num=03 \
     --step-name=apply --status=ok \
     --extra="$(jq -nc --arg m "$MIG_SCRIPT" '{migration:$m}')"
   ```

4. **Telemetry + progress global step-03** après dernière migration OK :
   ```bash
   bash skills/_shared/progress.sh step --skill=upgrade --story-id=_global \
     --step-num=03 --step-name=apply --status=ok
   ```

## Output

`.snap/` migré (schémas + paths cibles).

## Continue à

`step-04-validate.md`.
