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

### A. Bootstrap taxonomy + runtime cache (transactional edits)

Wrap the multi-set workflow in a runtime cache copy so an interrupted
`/snap:define --mode=vision` leaves `_taxonomy.json` untouched.

```bash
# 1. ensure the real taxonomy exists (idempotent, may create from scratch)
bash skills/_shared/taxonomy-state.sh init --project-root="$PWD"

# 2. spin up an ephemeral subject and snapshot the file into it
SUBJECT_ID=$(bash skills/_shared/cache-runtime.sh id-gen --prefix=define-vision)
bash skills/_shared/cache-runtime.sh init "$SUBJECT_ID" --project-root="$PWD"
CACHE_DIR=$(bash skills/_shared/cache-runtime.sh path "$SUBJECT_ID" --project-root="$PWD")
TAX_FILE="$PWD/.snap/manifests/_taxonomy.json"
cat "$TAX_FILE" > "$CACHE_DIR/_taxonomy.json"

# 3. redirect every taxonomy-state.sh call to the cache copy
export SNAP_TAXONOMY_FILE="$CACHE_DIR/_taxonomy.json"
```

Every `set-*` call in Tasks C-E now writes to the cache only — the real
file is not touched until Task F.5 flush. If the user aborts (Ctrl-C,
session exit, validation failure abandoned), the cache remains orphan
but `_taxonomy.json` is byte-identical to its pre-edit state.

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
  -d "$SNAP_TAXONOMY_FILE" \
  --spec=draft2020 --strict=false
```

`ajv` reads the cache copy via `$SNAP_TAXONOMY_FILE` (helpers also honour
that env var). Sur échec : surface l'erreur, propose ré-édition. **Ne pas
flusher** tant que la validation ne passe pas — le runtime cache absorbe
le rejet sans toucher au fichier réel.

### F.5 Flush atomique vers `_taxonomy.json`

Validation passée → commit la copie runtime en place avec un `mv`
atomique, puis purge le subject :

```bash
mv "$SNAP_TAXONOMY_FILE" "$TAX_FILE"
unset SNAP_TAXONOMY_FILE
bash skills/_shared/cache-runtime.sh purge "$SUBJECT_ID" --project-root="$PWD"
```

À partir de cette ligne, toute commande `taxonomy-state.sh` ré-attaque
le vrai `_taxonomy.json` (env var purgée).

### G. Telemetry + step progress

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
```

### H. Chain to next mode (or finish)

Frontmatter is terminal by default. Runtime branches dynamically based on
the user's intent — avoids re-invoking `/snap:define`, re-loading SKILL.md
and re-running the routeur.

`AskUserQuestion` (multiSelect: false) :

> "Vision saisie. Continuer ?"
> - "Mode journey — édit parcours utilisateur"
> - "Mode story — générer un PRD livrable"
> - "Terminé"

- **Terminé** : call `progress.sh finish --status=ok` then
  `define-state.sh wipe`. Stop.
- **Mode journey** : do NOT call `finish` or `wipe`. Patch the state mode
  and re-enter the journey handler in the same session :
  ```bash
  bash skills/_shared/define-state.sh init \
    --project-root="$PWD" --define-mode=journey
  ```
  Then jump to `step-00-journey-edit.md` (skip the routeur confirmation
  prompt — the user already confirmed by picking this option).
- **Mode story** : same idea, swap `--define-mode=story` and jump to
  `step-00-story-init.md`. The current `progress` skill-run entry stays
  open and accumulates the story steps.

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

_Terminal by default — runtime branching in Task H may chain to
`step-00-journey-edit.md` or `step-00-story-init.md` without exiting
the session._
