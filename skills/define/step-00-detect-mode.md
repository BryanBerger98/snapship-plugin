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
  `--feature=NN-slug`, `--epic=PARENT_EPIC_ID`.

## Tasks

### A. Parse args

1. Parse `--mode=` → si présent et ∈ {vision, journey, story} → bypass détection, jump direct au handler.
2. Si `--resume` présent **avec** un `define_mode` cached dans
   `.snap/.define-state.json` → réutiliser le mode caché et reprendre via
   `progress.sh resume`.
3. Sinon : passer à la détection LLM (étape B).

### B. Détection LLM (concertation)

Lire `RAW_INPUT` et classifier selon mots-clés :

| Mode | Indicateurs (FR/EN) |
|------|---------------------|
| `vision`  | « vision produit », « north star », « principes », « ambition », "product vision", "north star", "principles", "guiding values" |
| `journey` | « parcours », « flow », « étapes », « experience », "user journey", "flow", "steps", "experience map" |
| `story`   | _défaut_ — toute description de feature livrable, problem/solution, AC, persona |

Heuristique de scoring : compter les mentions par catégorie. Si égalité ou
ambiguïté → `story` (fallback safe).

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
  --mode="$define_mode"

bash skills/_shared/define-state.sh set define_mode "$define_mode" \
  --project-root="$PWD"
```

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

- `RAW_INPUT` vide + pas de `--mode=` → fallback `story` + warning UX
  "Mode auto-détecté `story` (aucun input distinctif). Préciser via `--mode=` au prochain run."
- User refuse 2 fois → abort propre avec `progress.sh step --status=fail`.

## Next step

→ Dépend de `define_mode` (voir tableau F).
