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

### A. Bootstrap taxonomy

```bash
bash skills/_shared/taxonomy-state.sh init --project-root="$PWD"
```

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
  -d .snap/manifests/_taxonomy.json \
  --spec=draft2020 --strict=false
```

### H. Telemetry + progress + cleanup

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

bash skills/_shared/progress.sh finish \
  --project-root="$PWD" \
  --skill=define \
  --story-id=_global \
  --status=ok

bash skills/_shared/define-state.sh wipe --project-root="$PWD"
```

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

_None — terminal step._
