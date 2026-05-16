---
step: 02-write
next_step: 03-update
description: Écrit le contenu pull dans le staging local approprié (.snap/PRDs/, designs/, wireframes/, tickets/).
---

# step-02 — write staging local

## Tâches

1. **Pour chaque target ok** dans `.snap/.fetch-cache/` :
   - Détermine staging path via `bash skills/_shared/sync-push.sh staging-path
     --story-id=$FID --kind=$KIND`.
   - Crée parent dirs si absents.
   - `cp` du fichier cache vers staging.

2. **PRDs (markdown)** : écrit tel quel `.snap/PRDs/{slug}.md`.

3. **Galleries (markdown)** : `.snap/designs/{slug}/gallery.md` ou
   `.snap/wireframes/{slug}/gallery.md`.

4. **Design files** : si Figma → écrit un descripteur JSON ou screenshots dans
   `.snap/designs/{slug}/figma-context.json`. Pas de tentative de copie binaire
   complète — c'est référencé via URL.

5. **Tickets** : `.snap/tickets/{slug}.json` — liste tickets sérialisée.

6. **Skip si `--dry-run`** : log "DRY: would write $TARGET → $PATH".

7. **Telemetry + progress** :
   ```bash
   bash skills/_shared/telemetry.sh log --skill=fetch --step-num=02 --step-name=write --status=ok
   bash skills/_shared/progress.sh step --skill=fetch --story-id=_global \
     --step-num=02 --step-name=write --status=ok
   ```

## Continue à

`step-03-update.md`.
