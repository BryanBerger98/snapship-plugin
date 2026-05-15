# Migrations snap

Framework migrations workspace local (.snap/) entre versions snap.

## Comment ajouter une migration

1. Bump `current_version` dans `registry.json`.
2. Ajouter une entrée dans `registry.json.migrations[]` :
   - `from` / `to` (semver exact)
   - `script` (filename `vX.Y.Z_to_vA.B.C.sh` dans ce dir)
   - `breaking` (true/false) — bloque skills si MAJOR mismatch
   - `summary` (1 phrase courte)
   - `decisions[]` — questions `AskUserQuestion` si breaking, sinon `[]`
3. Écrire le script bash :
   - Idempotent (re-run safe — exit 0 si déjà appliqué)
   - Reçoit `SNAP_PROJECT_ROOT`, `SNAP_DECISIONS_JSON` (env vars)
   - `SNAP_DECISIONS_JSON` = `{ "<decision_key>": "<value>" }`
   - Exit 0 = success, 1 = fail (le skill rollback depuis backup)
   - Logue progress lisible sur stdout

## Test local

```bash
SNAP_PROJECT_ROOT=/tmp/snap-test \
SNAP_DECISIONS_JSON='{"old_workspace":"backup"}' \
bash skills/_shared/migrations/v0.6.0_to_v1.0.0.sh
```

## Conventions decisions

| Champ | Sens |
|---|---|
| `key` | Slug stable, utilisé comme clé dans `SNAP_DECISIONS_JSON` |
| `question` | Texte AskUserQuestion |
| `header` | Tag court (< 12 chars) |
| `condition` | Optionnel — clé pré-détectée par `step-00-detect` qui décide s'il faut poser la question |
| `options[].value` | Slug stable passé au script |
| `default` | Valeur par défaut si user skip |

## Chain resolver

`step-00-detect.md` lit `registry.json` et résout la chaîne :
`current → ... → target`. Si chain.has_breaking, exige confirmation utilisateur.
