---
step: 00-vision-edit
description: Mode vision — édit workspace.vision / workspace.principles[] / workspace.north_star dans .snap/manifests/_taxonomy.json. Terminal. Pas de création de page doc auto (vision = artefact local v1.1).
---

# step-00-vision-edit — mode vision

Édition guidée des champs **workspace** de `.snap/manifests/_taxonomy.json` :
vision narrative, principes produit, métrique north star. Terminal step pour
le mode vision.

## Inputs

- `RAW_INPUT` (depuis router)
- `_taxonomy.json` existant (créé si absent par `taxonomy-state.sh init`)
- `define_mode = "vision"` dans `.snap/.define-state.json`

## Tasks

### A. Bootstrap taxonomy

```bash
bash skills/_shared/taxonomy-state.sh init --project-root="$PWD"
```

Idempotent — laisse l'existant intact.

### B. Lire l'état actuel

```bash
CURRENT_WS=$(bash skills/_shared/taxonomy-state.sh get-workspace --project-root="$PWD")
CURRENT_VISION=$(echo "$CURRENT_WS" | jq -r '.vision // ""')
CURRENT_PRINCIPLES=$(echo "$CURRENT_WS" | jq -c '.principles // []')
CURRENT_METRIC=$(echo "$CURRENT_WS"   | jq -r '.north_star.metric // ""')
```

Annoncer à l'user ce qui est déjà rempli (et propose édit / écrasement).

### C. Vision narrative

Via `AskUserQuestion` (free text) :

> "Vision produit (qui, quel changement, pourquoi maintenant) — paragraphe libre.
> Existant : `{{CURRENT_VISION}}` (laisse vide pour conserver)."

Validation :
- ≥ 50 caractères
- contient au moins un verbe d'action (best-effort, langue dépendante du `--lang`)

Si vide → conserver l'existant.

Persistance :
```bash
bash skills/_shared/taxonomy-state.sh set-vision "$NEW_VISION" \
  --project-root="$PWD"
```

### D. Principes produit

Via `AskUserQuestion` (multi-line free text) :

> "Principes produit (un par ligne, max 7). Existant :
> `{{CURRENT_PRINCIPLES (joined)}}`. Laisser vide pour conserver."

Parse → tableau JSON. Validation :
- 0 à 7 entrées
- chaque entrée ≥ 5 caractères
- unicité (set)

Persistance :
```bash
bash skills/_shared/taxonomy-state.sh set-principles "$PRINCIPLES_JSON" \
  --project-root="$PWD"
```

### E. North star metric

Via `AskUserQuestion` (multiSelect: false) :
- Activation rate
- Weekly active users (WAU)
- Revenue / ARR
- Retention W4
- Custom (free text follow-up)

Puis 3 follow-ups free text :
- Valeur actuelle (`unknown` accepté)
- Valeur cible
- Horizon (ex. `Q3 2026`, `6 mois`)

Persistance :
```bash
bash skills/_shared/taxonomy-state.sh set-north-star \
  "$METRIC" "$CURRENT" "$TARGET" "$HORIZON" \
  --project-root="$PWD"
```

### F. Validation finale

```bash
bash skills/_shared/taxonomy-state.sh validate --project-root="$PWD"
ajv validate \
  -s skills/_shared/schemas/taxonomy.schema.json \
  -d .snap/manifests/_taxonomy.json \
  --spec=draft2020 --strict=false
```

Sur échec : surface l'erreur, propose ré-édition.

### G. Telemetry + progress

```bash
bash skills/_shared/telemetry.sh log \
  --project-root="$PWD" \
  --skill=define \
  --step-num=00 \
  --step-name=vision-edit \
  --status=ok \
  --extra="{\"mode\":\"vision\"}"

bash skills/_shared/progress.sh step \
  --project-root="$PWD" \
  --skill=define \
  --story-id=_global \
  --step-num=00 \
  --step-name=vision-edit \
  --status=ok

bash skills/_shared/progress.sh finish \
  --project-root="$PWD" \
  --skill=define \
  --story-id=_global \
  --status=ok
```

### H. Cleanup

```bash
bash skills/_shared/define-state.sh wipe --project-root="$PWD"
```

## What this step does NOT do

- ❌ Créer une page documentation distante automatiquement.
- ❌ Toucher `domains` ou `journeys` (mode journey les édite).
- ❌ Générer PRD (mode story).

## Acceptance check

- `.snap/manifests/_taxonomy.json.workspace.vision` non vide.
- `.workspace.principles` array uniquement valeurs uniques ≥ 5 chars.
- `.workspace.north_star.metric` non vide.
- Validation schema OK.

## Next step

_None — terminal step._
