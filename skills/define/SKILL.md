---
name: define
description: Multimode router skill — `vision` (workspace narrative + principles + north star), `journey` (user journeys + steps + outcomes), or `story` (per-feature PRDs in change-request format). Auto-detects mode from prompt or `--mode=` flag, runs LLM concertation, then branches to the correct sub-flow. Story mode pushes PRDs to AFFiNE/Notion via docs-adapter and materializes `.snap/manifests/{slug}.manifest.json` per feature.
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, AskUserQuestion
---

# /snap:define — product definition skill (multimode)

Run this skill to **bootstrap or update product knowledge** : vision, parcours
utilisateur, ou PRDs change-request. Un routeur central (`step-00-detect-mode`)
choisit le mode selon le prompt ou le flag `--mode=`.

## Prerequisite

Run `/snap:init` once per project first. This skill exits early if
`snap.config.json` is missing.

## Modes

| Mode | When to use | Terminal step |
|------|-------------|---------------|
| `vision` | Définir/éditer la vision produit, principes, north star metric | `step-00-vision-edit` |
| `journey` | Créer / refacto / split un parcours utilisateur (steps + outcomes) | `step-00-journey-edit` |
| `story` | Bootstrap ou étendre les PRDs des features (change-request) | `step-01..05` |

Le routeur `step-00-detect-mode` :

1. Parse `--mode=` si fourni → applique direct (skip détection LLM).
2. Sinon analyse `RAW_INPUT` via mots-clés (FR/EN) + LLM concertation pour
   proposer un mode.
3. Confirme via `AskUserQuestion` avant branchement.
4. Persiste `define_mode` dans `.snap/.define-state.json`.

### Mots-clés (best-effort, indicatifs)

| Mode | FR | EN |
|------|----|----|
| vision | vision, mission, principes, métrique, ambition | vision, mission, principles, north star, metric |
| journey | parcours, flow, étapes utilisateur, scénario | journey, flow, user steps, scenario |
| story | feature, story, PRD, fonctionnalité, ticket | feature, story, PRD, ticket |

## When to use

- Greenfield project after init: démarrer en mode `vision` puis `journey`
  puis `story`.
- Existing project: chaque mode est idempotent — relancer pour étendre /
  refactor.
- Resume: `--resume` (`-r`) reprend depuis la dernière step in-flight de
  `.snap/progress.json` (tous modes confondus).

## Pipeline

Tous les modes partagent un routeur unique en step-00. Chaque mode est ensuite
isolé dans son propre fichier markdown avec frontmatter `next_step`.

### Mode vision (terminal en step-00)

| # | Step | Purpose |
|---|------|---------|
| 00 | `step-00-detect-mode.md` | Routeur — détecte le mode et branche |
| 00 | `step-00-vision-edit.md` | Édite workspace.vision/principles/north_star dans `_taxonomy.json` |

### Mode journey (terminal en step-00)

| # | Step | Purpose |
|---|------|---------|
| 00 | `step-00-detect-mode.md` | Routeur |
| 00 | `step-00-journey-edit.md` | Crée/refacto/split journeys (steps+outcomes) dans `_taxonomy.json` |

### Mode story (5 steps après routeur)

| # | Step | Purpose |
|---|------|---------|
| 00 | `step-00-detect-mode.md`  | Routeur |
| 00 | `step-00-story-init.md`   | Parse args, require config, detect codebase, branch greenfield vs extension |
| 01 | `step-01-vision.md`       | Capture vision + north star metric (cache state) |
| 02 | `step-02-personas.md`     | Ask 1-N personas |
| 03 | `step-03-features.md`     | Ask features list (priorities, parent Epic, domains, impacted journeys) |
| 04 | `step-04-render.md`       | Render `.snap/PRDs/{slug}.md` + materialize `manifests/{slug}.manifest.json` |
| 05 | `step-05-publish.md`      | Push PRD page, ensure domain + journey pages exist, ack refs (trash staging) |

## Args

```
/snap:define [--mode=vision|journey|story] [--resume|-r] [--lang=fr|en]
             [--feature=NN-slug] [--epic=PARENT_EPIC_ID]
```

- `--mode` : force le mode et skip la détection LLM. Si absent, le routeur
  détecte depuis le prompt et confirme.
- `--resume` / `-r` : reprend depuis la dernière step in-flight dans
  `.snap/progress.json`. Partial-match story_id (`01` → `01-auth`). Si pas de
  run in-flight, fall-through au routeur.
- `--lang` : force la langue (default: detect from existing or ask).
- `--feature` : mode story uniquement — skip greenfield, jump à la PRD
  per-feature pour un `story_id` existant.
- `--epic` : mode story uniquement — reporter l'ID Epic parent sur toutes
  les features capturées dans cette run (skip la question parent Epic).

## Examples

```bash
# Mode détecté auto (concertation LLM)
/snap:define "Je veux ajouter un parcours d'onboarding rapide"
# → mode journey proposé, confirmé via AskUserQuestion

# Mode forcé via flag
/snap:define --mode=vision
# → branche direct sur step-00-vision-edit

# Mode story + Epic parent imposé
/snap:define --mode=story --epic=AUTH-1
# → step-03 skip la question parent Epic, applique AUTH-1 à toutes features

# Resume
/snap:define -r
# → reprend la step in-flight, peu importe le mode
```

## Outputs

### Mode vision

Persistent :
- `.snap/manifests/_taxonomy.json.workspace.vision/principles/north_star`

### Mode journey

Persistent :
- `.snap/manifests/_taxonomy.json` — journeys avec `state` (`draft` | `synced`),
  `steps[]`, `outcomes[]`.

Note : `state=draft` (sans `page_id`) reste local. La page distante est créée
par `/snap:doc-update` post-validation.

### Mode story

Local (staging — trashed après push réussi en step-05) :
- `.snap/PRDs/{story_id}.md` — PRD markdown source.

Local (persistent — pointeurs distants) :
- `.snap/manifests/{story_id}.manifest.json` — schema_version, story_id,
  story_name, state, priority, parent_epic_id|parent_epic_title+pending,
  domains[], impacted_journeys[], refs.{prd, …} après publish.
- `.snap/manifests/_taxonomy.json` — domain + journey page IDs cachés
  (idempotent entre re-runs et entre features).

Runtime (tous modes, gitignored) :
- `.snap/progress.json` — état skill in-flight, purgé sur terminal-step ok.
- `.snap/telemetry.ndjson` — log événements append-only.

Remote (mode story uniquement — single source of truth) :
- Page PRD à `{prd_root}/{YYYY}/{MM-YYYY}/{NN-feature}` (archive immuable,
  taggée avec domaines impactés).
- Pages domain + journey sous `{functional_root}/{domain}/{journey}` (spec
  vivante, body rempli plus tard par `/snap:doc-update`).

v0.1 `prd-global.md` et v0.2 `meta.json` sont droppés — voir
`docs/contributing/decisions.md` "PRD archive vs doc fonctionnelle vivante" +
"Manifest unifié v1.0".

## How to run

1. Read `step-00-detect-mode.md` (router) — toujours le point d'entrée sauf
   `--resume` qui réoriente.
2. Suivre les instructions exactement, branche vers le mode confirmé, puis
   suivre le fichier référencé en `next_step`.
3. S'arrêter quand une step n'a pas de `next_step` (terminal) ou si l'user
   abort.

Tous les modes sont **idempotents** — relancer step-NN avec les mêmes inputs
produit le même output. Les re-runs sont safe (step-05 skip les features déjà
synced, `_taxonomy.json` mutations sont mergeantes).
