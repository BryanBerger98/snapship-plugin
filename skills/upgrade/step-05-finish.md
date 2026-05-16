---
step: 05-finish
next_step: null
description: Bump snap.config.json.version, trash ephemeral files (.upgrade-plan, .upgrade-decisions), suggère /snap:fetch + reprise progress.
terminal: true
---

# step-05 — finish

Boucle la migration : versions bumpées, ephémères trashés, prochaine étape suggérée.

## Tâches

1. **Skip writes si `--dry-run`** : log "DRY: skip bump + cleanup".

2. **Bump `snap.config.json.version`** :
   ```bash
   jq --arg v "$TARGET" '.version = $v' snap.config.json > snap.config.json.tmp
   mv snap.config.json.tmp snap.config.json
   ```
   (Idempotent — peut être déjà au target depuis la migration script.)

3. **Trash ephemeral** :
   ```bash
   trash .snap/.upgrade-plan.json .snap/.upgrade-decisions.json 2>/dev/null || true
   ```

4. **Detect in-flight** : `bash skills/_shared/progress.sh list`
   - Si autres skills in-flight (autres que `upgrade`) → mentionne reprise possible :
     "Skill `define` (feature 01-auth) était in-flight au step `02-personas`.
      Reprends avec `/snap:define --resume`."

5. **Telemetry + progress finish** :
   ```bash
   bash skills/_shared/telemetry.sh log --skill=upgrade --step-num=05 --step-name=finish --status=ok \
     --extra="$(jq -nc --arg t "$TARGET" '{target:$t}')"
   bash skills/_shared/progress.sh step --skill=upgrade --story-id=_global \
     --step-num=05 --step-name=finish --status=ok
   bash skills/_shared/progress.sh finish --skill=upgrade --story-id=_global --status=ok
   ```

6. **Summary output** :
   ```
   ✅ /snap:upgrade — migration {from} → {target} terminée

   Backup local   : .snap.bak-v{from}-{ts}/  (trash manuellement plus tard)
   Workspace      : .snap/
   Config version : {target}

   Prochaine étape recommandée :
     /snap:fetch --all       # re-sync depuis remote (absorbe drift)
   ```

## Terminal

Skill terminé. Reprise possible si autre skill in-flight.
