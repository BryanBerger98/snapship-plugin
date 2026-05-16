---
step: 00-journey-edit
description: Mode journey — édit local .snap/manifests/_taxonomy.json (domains[*].journeys[*] ou top-level journeys[*]) avec sous-mode create/refactor/split. Steps[] + outcomes[]. Pas de page doc auto (créée par /doc-update post-validation).
---

# step-00-journey-edit — mode journey

Édition guidée des parcours utilisateur dans `.snap/manifests/_taxonomy.json`.
Terminal step pour le mode journey.

## Inputs

- `RAW_INPUT` (router)
- `_taxonomy.json` existant
- `define_mode = "journey"`

## Tasks

### A. Bootstrap taxonomy + runtime cache (transactional edits)

Wrap the multi-set workflow in a runtime cache copy so an interrupted
`/snap:define --mode=journey` leaves `_taxonomy.json` untouched.

```bash
# 1. ensure the real taxonomy exists (idempotent)
bash skills/_shared/taxonomy-state.sh init --project-root="$PWD"

# 2. spin up an ephemeral subject and snapshot the file into it
SUBJECT_ID=$(bash skills/_shared/cache-runtime.sh id-gen --prefix=define-journey)
bash skills/_shared/cache-runtime.sh init "$SUBJECT_ID" --project-root="$PWD"
CACHE_DIR=$(bash skills/_shared/cache-runtime.sh path "$SUBJECT_ID" --project-root="$PWD")
TAX_FILE="$PWD/.snap/manifests/_taxonomy.json"
cat "$TAX_FILE" > "$CACHE_DIR/_taxonomy.json"

# 3. redirect every taxonomy-state.sh call to the cache copy
export SNAP_TAXONOMY_FILE="$CACHE_DIR/_taxonomy.json"
```

Every helper call in Tasks B-F now writes to the cache only — the real
file is not touched until Task G.5 flush. Interrupting mid-edit leaves
the cache orphan but `_taxonomy.json` byte-identical to its pre-edit
state.

### B. Choisir sous-mode

Via `AskUserQuestion` (multiSelect: false) :

- `create` — nouveau parcours
- `refactor` — modifier un parcours existant
- `split` — décomposer un parcours en N

Cache `journey_submode` via `define-state.sh set journey_submode "$submode"`.

### C. Sous-mode `create`

1. **Domain parent** : `AskUserQuestion` parmi domains existants (récupéré via
   `taxonomy-state.sh list-domains`) + option `_` pour top-level + option
   "Nouveau domain" (libre — créer via `add-domain` après avoir poussé une
   page placeholder via `/doc-update` ou en draft sans page_id si helper
   supporte).

   _Phase D' : si nouveau domain demandé sans `page_id`, refuser proprement
   et inviter à passer par `/define --mode=story` qui crée le squelette
   domain (mode journey n'auto-crée pas de domain)._

2. **Slug + titre** : `AskUserQuestion` free text → slug kebab auto. Refuser
   collision via `taxonomy-state.sh has-journey "$dslug" "$slug"`.

3. **Création draft** :
   ```bash
   bash skills/_shared/taxonomy-state.sh draft-journey "$dslug" "$slug" "$title" \
     --project-root="$PWD"
   ```

4. **Steps + outcomes** : sous-section D ci-dessous.

### D. Sous-mode `refactor`

1. Lister journeys existants :
   ```bash
   bash skills/_shared/taxonomy-state.sh list-journeys --project-root="$PWD"
   ```
   Présenter via `AskUserQuestion` (multiSelect: false).

2. Charger l'état courant :
   ```bash
   bash skills/_shared/taxonomy-state.sh get-journey "$dslug" "$jslug" \
     --project-root="$PWD"
   ```

3. Boucle d'édition : présenter steps[] + outcomes[] actuels, demander
   add/remove/reorder/update via `AskUserQuestion`. Stop sur "Done".

4. Persistance via `set-journey-content` (étape E).

### E. Sous-mode `split`

1. Choisir parcours source (comme refactor.1).
2. Demander N nouveaux noms + slugs.
3. Pour chaque nouveau parcours :
   - `draft-journey <dslug> <new_slug> <new_title>`
   - Demander à l'user de répartir les steps de la source.
4. Marquer la source `state=draft` + ajouter outcome `"split into: a,b,c"` ou
   demander à l'user si suppression (manuel via jq, hors helper pour éviter
   destructive default).

### F. Steps + outcomes (commun create/refactor/split)

Via `AskUserQuestion` (free text multiline) :

> "Steps du parcours (un par ligne — format `<titre> | <description optionnelle>`)"

Parse :
```bash
STEPS_JSON=$(printf '%s' "$INPUT" | jq -R -s -c '
  split("\n") | map(select(length > 0))
  | map(split("|") | { title: (.[0] | gsub("^\\s+|\\s+$";"")),
                       description: (.[1] // "" | gsub("^\\s+|\\s+$";"")) })
  | map(if .description == "" then del(.description) else . end)
')
```

Outcomes :
> "Outcomes attendus (un par ligne)"

```bash
OUTCOMES_JSON=$(printf '%s' "$INPUT" | jq -R -s -c '
  split("\n") | map(select(length > 0))
')
```

Persistance :
```bash
bash skills/_shared/taxonomy-state.sh set-journey-content \
  "$dslug" "$jslug" "$STEPS_JSON" "$OUTCOMES_JSON" \
  --project-root="$PWD"
```

### G. Validation

```bash
bash skills/_shared/taxonomy-state.sh validate --project-root="$PWD"
ajv validate \
  -s skills/_shared/schemas/taxonomy.schema.json \
  -d "$SNAP_TAXONOMY_FILE" \
  --spec=draft2020 --strict=false
```

`ajv` reads the cache copy (the env var redirects helpers; the schema
file path stays absolute). **Ne pas flusher** tant que la validation
ne passe pas — le runtime cache absorbe le rejet sans toucher au
fichier réel.

### G.5 Flush atomique vers `_taxonomy.json`

```bash
mv "$SNAP_TAXONOMY_FILE" "$TAX_FILE"
unset SNAP_TAXONOMY_FILE
bash skills/_shared/cache-runtime.sh purge "$SUBJECT_ID" --project-root="$PWD"
```

À partir de cette ligne, toute commande `taxonomy-state.sh` ré-attaque
le vrai `_taxonomy.json`.

### H. Telemetry + step progress

```bash
bash skills/_shared/telemetry.sh log \
  --project-root="$PWD" \
  --skill=define \
  --step-num=00 \
  --step-name=journey-edit \
  --status=ok \
  --extra="{\"submode\":\"$submode\",\"slug\":\"$jslug\"}"

bash skills/_shared/progress.sh step \
  --project-root="$PWD" \
  --skill=define \
  --story-id=_global \
  --step-num=00 \
  --step-name=journey-edit \
  --status=ok
```

### I. Chain to next mode (or finish)

Frontmatter is terminal by default. Runtime branches dynamically based on
the user's intent — avoids re-invoking `/snap:define`, re-loading SKILL.md
and re-running the routeur.

`AskUserQuestion` (multiSelect: false) :

> "Parcours saisi. Continuer ?"
> - "Mode vision — édit workspace produit"
> - "Mode story — générer un PRD livrable"
> - "Terminé"

- **Terminé** : call `progress.sh finish --status=ok` then
  `define-state.sh wipe`. Stop.
- **Mode vision** : do NOT call `finish` or `wipe`. Patch the state mode
  and re-enter the vision handler in the same session :
  ```bash
  bash skills/_shared/define-state.sh init \
    --project-root="$PWD" --define-mode=vision
  ```
  Then jump to `step-00-vision-edit.md` (skip the routeur confirmation
  prompt — the user already confirmed by picking this option).
- **Mode story** : same idea, swap `--define-mode=story` and jump to
  `step-00-story-init.md`. The current `progress` skill-run entry stays
  open and accumulates the story steps.

## What this step does NOT do

- ❌ Pousser de page documentation distante (déféré à `/snap:doc-update`).
- ❌ Toucher `workspace.vision/principles/north_star` (mode vision).
- ❌ Générer PRD (mode story).

## Acceptance check

- Journey draftée a `state=draft` (sans `page_id`) ou `state=synced` (existant).
- `steps[].title` non vide pour chaque entrée.
- `outcomes[]` ne contient aucune valeur dupliquée.
- Validation schema OK.

## Next step

_Terminal by default — runtime branching in Task I may chain to
`step-00-vision-edit.md` or `step-00-story-init.md` without exiting
the session._
