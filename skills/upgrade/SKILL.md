---
name: upgrade
description: Migre le workspace local `.snap/` (ou ancien `.claude/product/`) vers la version snap installée. Détecte version courante, plan la chaîne de migrations, demande les décisions utilisateur pour breaking changes, backup, applique, valide.
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, AskUserQuestion
---

# /snap:upgrade — workspace migration

Migre un workspace existant (`.snap/` ou ancien `.claude/product/`) vers la
version snap installée (lue depuis `.claude-plugin/plugin.json`). Aligne
schémas, chemins, et formats. Idempotent — peut être re-exécuté.

## Quand utiliser

- Mismatch détecté par un skill (`MAJOR version mismatch` au boot).
- Mise à jour manuelle du plugin (`git pull` du plugin, install nouvelle release).
- Vérification : `--dry-run` montre le plan sans rien modifier.

## Pipeline

| # | Step | Purpose |
|---|------|---------|
| 00 | `step-00-detect.md`  | Lit versions courante + cible, résout chaîne migrations, détecte conditions |
| 01 | `step-01-confirm.md` | Affiche plan, AskUserQuestion pour décisions breaking |
| 02 | `step-02-backup.md`  | Backup `.snap/` (ou `.claude/product/`) → `.snap.bak-v{x}-{ts}/` |
| 03 | `step-03-apply.md`   | Exécute chaque migration script, dans l'ordre |
| 04 | `step-04-validate.md`| Valide schémas (manifest, taxonomy, config) + paths |
| 05 | `step-05-finish.md`  | Bump versions plugin/config, suggère `/snap:fetch` |

## Args

```
/snap:upgrade [--target=VERSION] [--dry-run] [--auto] [--from=VERSION]
```

- `--target=VERSION` : version cible (défaut : version plugin installée).
- `--dry-run` : affiche plan sans backup/modif. Idéal pour preview.
- `--auto` : applique les `default` de chaque décision sans demander.
- `--from=VERSION` : force la version source si la détection rate (ex : workspace partiellement migré).

## Outputs

- `.snap/` migré au schéma cible.
- `.snap.bak-v{from}-{ts}/` backup (sauf `--dry-run`).
- `snap.config.json.version` = version cible.
- Telemetry entrées `/upgrade step-NN ... — ok`.

## Détection de version

Source de vérité (par priorité) :
1. `.snap/manifests/_taxonomy.json.schema_version`
2. `.snap/manifests/*.manifest.json.schema_version` (premier trouvé)
3. `snap.config.json.version`
4. Si `.claude/product/` existe et `.snap/` absent → `0.6.0` présumé.

## How to run a step

Lit le fichier step actif (`step-00-detect.md` d'abord), suit exactement, puis
saute au fichier référencé dans son `next_step` frontmatter. Stop sur step
terminal ou abort user.

Chaque step est **idempotent** — re-run safe.

## Failure handling

- Migration script exit ≠ 0 → rollback automatique depuis backup, abort.
- `--dry-run` + erreur de plan → liste les blockers, exit 0.
- Validation fail step-04 → report mais ne rollback pas (workspace migré, juste schemas à corriger manuellement).

## Suggest next

Après succès :
- `/snap:fetch --all` (recommandé — re-sync depuis remote pour absorber tout drift).
- Reprise de skill in-flight si `progress.json` non vide.
