---
step: 02-backup
next_step: 03-apply
description: Backup le workspace courant (.snap/ ou .claude/product/) vers .snap.bak-v{from}-{ts}/ avant migration.
---

# step-02 — backup workspace

Snapshot complet du workspace courant pour rollback en cas d'échec.

## Tâches

1. **Skip si `--dry-run`** : log "DRY: skip backup" et continue.

2. **Skip si decision `old_workspace == keep`** pour la migration en cours :
   "Backup skip (decision=keep — workspace original gardé intact)".

3. **Détermine source** :
   - Si `.snap/` existe → backup `.snap/`.
   - Sinon si `.claude/product/` existe → backup `.claude/product/`.
   - Sinon, rien à backup, continue.

4. **Crée backup** :
   ```bash
   NOW=$(date -u +"%Y%m%dT%H%M%SZ")
   BACKUP_DIR=".snap.bak-v${FROM}-${NOW}"
   cp -R "$SOURCE_DIR" "$BACKUP_DIR"
   ```

5. **Validation** : vérifie taille backup vs source identique
   (`du -sk` comparable).

6. **Trace path backup** dans `.snap/.upgrade-plan.json` pour step-03 rollback.

7. **Telemetry + progress** :
   ```bash
   bash skills/_shared/telemetry.sh log --skill=upgrade --step-num=02 --step-name=backup --status=ok \
     --extra="$(jq -nc --arg p "$BACKUP_DIR" '{backup_path:$p}')"
   bash skills/_shared/progress.sh step --skill=upgrade --feature-id=_global \
     --step-num=02 --step-name=backup --status=ok
   ```

## Important

- **Garde le backup forever**. L'utilisateur trash manuellement.
- N'écrase JAMAIS un backup existant — ajoute suffixe `-{N}` si collision.

## Continue à

`step-03-apply.md`.
