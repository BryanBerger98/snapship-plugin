---
step: 00-detect-mode
next_step: 00-story-init
description: Router multimode /define — détecte intent (vision/journey/story) depuis input user (+ flag --mode= opt-in), branche vers handler dédié. Vision et journey éditent _taxonomy.json local (pas de page doc auto). Story = flow PRD livrable (default).
---

# step-00 — detect mode (router)

Entry point pour `/snap:define`. Détecte le mode d'invocation puis branche vers
le handler approprié :

- `vision` → `step-00-vision-edit.md` (édit `_taxonomy.json.workspace`)
- `journey` → `step-00-journey-edit.md` (édit `_taxonomy.json.{domains[].journeys,journeys}`)
- `story` → `step-00-story-init.md` (flow PRD livrable, default)

## Inputs

- `RAW_INPUT` : message libre user fourni à `/snap:define`.
- Args : `--mode=<vision|journey|story>` (opt-in), `--lang=fr|en`, `--resume`/`-r`,
  `--story=NN-slug` (alias déprécié : `--feature=`), `--epic=PARENT_EPIC_ID`.

## Tasks

### A. Parse args

1. Parse `--mode=` → si présent et ∈ {vision, journey, story} → bypass détection, jump direct au handler.
2. Si `--resume` présent **avec** un `define_mode` cached dans
   `.snap/.define-state.json` → réutiliser le mode caché et reprendre via
   `progress.sh resume`.
3. Sinon : passer à la détection LLM (étape B).

### B. Détection LLM (concertation)

1. **Charger le lexique** via `Read` : `skills/define/_keywords.json`. Fichier
   versionné (`version: 1`) contenant `categories.{vision,journey,story}.{fr,en}`.
   Progressive disclosure — chargé uniquement par le routeur, jamais par
   `SKILL.md`.

2. **Scoring** :
   - Normaliser `RAW_INPUT` en lowercase.
   - Pour chaque catégorie ∈ {vision, journey, story}, fusionner `fr ∪ en`.
   - Compter les occurrences word-boundary (insensible à la casse) de chaque
     mot-clé dans `RAW_INPUT`.
   - Score catégorie = somme des occurrences.

3. **Résolution** :
   - Score max unique → ce mode.
   - Égalité ou tous scores à zéro → `ambiguous` (passe à Phase C pour
     demander à l'utilisateur ; **ne pas** auto-fallback `story`).

Le fichier `_keywords.json` est la **source unique** du routage. Toute
modification du lexique se fait là — le test `test-define-mode-detection.sh`
charge le même fichier et vérifie ≥ 90 % de classement correct sur un
corpus 10 FR + 10 EN par mode.

### C. Confirmation user

Via `AskUserQuestion` (multiSelect: false) :

> "Mode détecté : **{define_mode}**. Confirmer ?"
> - "Oui — proceed mode {define_mode}"
> - "Non — choisir un autre mode"

Si "Non" → second `AskUserQuestion` :
- "vision (édit workspace produit)"
- "journey (édit parcours utilisateur)"
- "story (générer PRD livrable)"

### D. Cache mode + initialise state

```bash
bash skills/_shared/define-state.sh init \
  --project-root="$PWD" \
  --lang="${lang:-en}" \
  --define-mode="$define_mode"
```

`cmd_init` est merge-aware : si le state existe déjà, seules les keys passées
en flag sont mises à jour. Si appel suivant (story-init) passe
`--codebase-mode=greenfield`, le `define_mode` cached ici survit.

### E. Progress

```bash
bash skills/_shared/progress.sh step \
  --project-root="$PWD" \
  --skill=define \
  --story-id=_global \
  --step-num=00 \
  --step-name=detect-mode \
  --status=ok \
  --extra="{\"define_mode\":\"$define_mode\"}"
```

### F. Branch

| `define_mode` | Next step |
|---------------|-----------|
| `vision`  | `step-00-vision-edit.md`  |
| `journey` | `step-00-journey-edit.md` |
| `story`   | `step-00-story-init.md`   |

Set `next_step` runtime variable accordingly. The frontmatter default
(`00-story-init`) covers the most common path; override when mode ∈
{vision, journey}.

## Acceptance check

- `.snap/.define-state.json` contains `define_mode ∈ {vision, journey, story}`.
- `progress.json` has step 00 detect-mode with `status=ok`.
- User confirmed the mode (or `--mode=` was explicit).

## Failure handling

- `RAW_INPUT` vide + pas de `--mode=` → score `ambiguous` → Phase C demande
  explicitement le mode (pas d'auto-pick silencieux).
- User refuse 2 fois → abort propre avec `progress.sh step --status=fail`.
- `_keywords.json` absent ou non parsable → abort avec message
  "lexique routeur introuvable — réinstaller plugin ou récupérer
  `skills/define/_keywords.json`".

## Next step

→ Dépend de `define_mode` (voir tableau F).
