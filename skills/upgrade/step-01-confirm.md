---
step: 01-confirm
next_step: 02-backup
description: Affiche le plan migration, pose les questions interactives (AskUserQuestion) pour chaque décision breaking active. Construit SNAP_DECISIONS_JSON.
---

# step-01 — confirm + collect decisions

Présente le plan, demande validation, collecte les décisions breaking.

## Tâches

1. **Lit le plan** depuis `.snap/.upgrade-plan.json` (écrit par step-00).

2. **Affiche le résumé** à l'utilisateur :
   ```
   /snap:upgrade — plan
     from   : 0.6.0
     target : 1.0.0
     chain  : v0.6.0_to_v1.0.0.sh (BREAKING)
     dry-run: false

   Résumé migration :
     - Move .claude/product/ → .snap/
     - Split features/{id}/ par type (PRDs/, manifests/, designs/, ...)
     - meta.json → manifests/{slug}.manifest.json
     - domains.json → manifests/_taxonomy.json
     - Drop progress.md, daemon mode, activity log, .config-resolved.json cache
   ```

3. **Décisions interactives** : pour chaque migration `chain[i].decisions[]`,
   filtre celles dont `condition` (si présent) match un `conditions[]` true du
   plan (sinon, garde la décision dans tous les cas).

   - Si `--auto` : utilise `default` de chaque décision.
   - Sinon : `AskUserQuestion` une question par décision active.

   Exemple d'appel `AskUserQuestion` pour `old_workspace` :
   ```json
   {
     "question": "Que faire de l'ancien dossier .claude/product/ ?",
     "header": "Legacy dir",
     "multiSelect": false,
     "options": [
       { "label": "Garder en backup (.snap.bak-v0.6.0-{ts}/) (Recommandé)",
         "description": "Backup conservé localement, trashable plus tard." },
       { "label": "Trash immédiat",
         "description": "Aucune trace locale, récupérable corbeille système." },
       { "label": "Laisser intact à côté",
         "description": "Garde .claude/product/ — migration partielle." }
     ]
   }
   ```

   Mappe la réponse au `value` correspondant dans `registry.json.options[].value`.

4. **Build `SNAP_DECISIONS_JSON`** :
   ```json
   {
     "old_workspace": "backup",
     "republish_prds": "skip",
     "tickets_no_tracker": "configure",
     "daemon_users": "session"
   }
   ```
   Persiste dans `.snap/.upgrade-decisions.json` (ephémère).

5. **Validation finale** : si `--dry-run`, court-circuite vers step-03 en mode dry.
   Sinon, demande confirmation finale (yes/no) sauf si `--auto`.

6. **Telemetry + progress** :
   ```bash
   bash skills/_shared/telemetry.sh log --skill=upgrade --step-num=01 --step-name=confirm --status=ok
   bash skills/_shared/progress.sh step --skill=upgrade --story-id=_global \
     --step-num=01 --step-name=confirm --status=ok
   ```

## Sortie

`.snap/.upgrade-decisions.json` rempli.

## Continue à

`step-02-backup.md` (sauf `--dry-run` qui saute à `step-03-apply.md`).
