---
step: 03-update
next_step: null
description: Met à jour manifest.refs.<kind>.synced_at + sync_status=synced. Trash ephemeral cache. Skill terminal.
terminal: true
---

# step-03 — update manifest refs + cleanup

## Tâches

1. **Pour chaque target ok**, appelle :
   ```bash
   bash skills/_shared/sync-fetch.sh ack \
     --feature-id=$FID --kind=$KIND \
     --content-file=.snap/.fetch-cache/${FID}-${KIND}.content \
     --platform=$PLAT --url=$URL [--page-id=$PID | --file-key=$FKEY | --project-id=$PRJ]
   ```
   sync-fetch.sh ack :
   - Copie content vers staging target (déjà fait au step-02 idéalement,
     mais ack ré-écrit pour atomicité).
   - Update `manifest.refs.{kind}.synced_at = now()` + `sync_status = "synced"`.

2. **Trash ephemeral** :
   ```bash
   trash .snap/.fetch-cache .snap/.fetch-plan.json 2>/dev/null || true
   ```

3. **Summary output** :
   ```
   ✅ /snap:fetch — N targets resync'd
     01-auth.prd          : synced (notion://abc-123)
     01-auth.design_file  : synced (figma://...)
     02-billing.tickets   : synced (linear://proj-xyz)
   ```

4. **Telemetry + progress finish** :
   ```bash
   bash skills/_shared/telemetry.sh log --skill=fetch --step-num=03 --step-name=update --status=ok
   bash skills/_shared/progress.sh step --skill=fetch --feature-id=_global \
     --step-num=03 --step-name=update --status=ok
   bash skills/_shared/progress.sh finish --skill=fetch --feature-id=_global --status=ok
   ```

5. **Suggest next** :
   - Si user a fetch un PRD pour édition : "Édite `.snap/PRDs/{slug}.md` puis lance
     `/snap:define --refresh=prd --feature={slug}` pour re-push."
   - Si `--check` a marqué dirty : "Re-run `/snap:fetch --feature={slug} --kind={k}` pour
     pull la version remote."

## Terminal

Skill terminé.
