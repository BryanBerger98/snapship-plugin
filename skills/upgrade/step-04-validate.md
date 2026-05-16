---
step: 04-validate
next_step: 05-finish
description: Valide les schémas (config, manifest, taxonomy, progress) et l'existence des paths attendus. Non-fatal — report warnings.
---

# step-04 — validate workspace

Sanity check post-migration.

## Tâches

1. **Skip si `--dry-run`** : "DRY: skip validation".

2. **Valide chaque schéma** via `ajv-cli` (déjà utilisé par load-config.sh) :
   ```bash
   for f in .snap/manifests/*.manifest.json; do
     [ -f "$f" ] || continue
     npx -y ajv-cli validate --spec=draft2020 -s skills/_shared/schemas/manifest.schema.json -d "$f" --strict=false
   done
   npx -y ajv-cli validate --spec=draft2020 -s skills/_shared/schemas/taxonomy.schema.json -d .snap/manifests/_taxonomy.json --strict=false
   npx -y ajv-cli validate --spec=draft2020 -s skills/_shared/schemas/progress.schema.json -d .snap/progress.json --strict=false
   bash skills/_shared/load-config.sh >/dev/null   # valide config aussi
   ```

3. **Vérifie paths cibles** :
   - `.snap/manifests/` existe
   - `.snap/manifests/_taxonomy.json` existe
   - `.snap/progress.json` existe
   - Pour chaque manifest : `story_id` matche le nom de fichier (`{slug}.manifest.json`).

4. **Vérifie absence legacy** :
   - `.claude/product/` doit être absent (sauf decision `keep`).
   - Pas de `meta.json` résiduel dans `.snap/`.
   - Pas de `progress.md` résiduel.
   - Pas de `domains.json` résiduel.

5. **Report** :
   ```
   ✅ schemas        : OK (N manifests, taxonomy, progress, config)
   ✅ paths          : OK
   ✅ legacy cleanup : OK
   ```
   Si fail → liste les blockers mais ne rollback pas (l'utilisateur peut corriger
   manuellement post-migration).

6. **Telemetry + progress** :
   ```bash
   bash skills/_shared/telemetry.sh log --skill=upgrade --step-num=04 --step-name=validate --status=ok
   bash skills/_shared/progress.sh step --skill=upgrade --story-id=_global \
     --step-num=04 --step-name=validate --status=ok
   ```

## Continue à

`step-05-finish.md`.
